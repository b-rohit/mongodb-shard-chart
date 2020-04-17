#!/bin/bash
TYPE=$1
retry_until_conf() {
  COUNTER=0
  res=$(eval 'mongo -u mongors1conf-admin -p qweasd --host indexer-mongocfg1:27017 --eval "rs.status().ok"')
  response=$?
  echo "response, $response"
  echo "res $res" 
  while [[ response -ne 0 ]] ; do
      sleep 2
      let COUNTER+=2
      echo "Waiting for mongo to initialize... ($COUNTER seconds so far)"
      mongo -u mongors1conf-admin -p qweasd --host indexer-mongocfg1:27017 --eval 'rs.status().ok'
      response=$?
  done
}
retry_until() {
  COUNTER=0
  grep -q 'waiting for connections on port' /var/log/mongodb.log
  while [[ $? -ne 0 ]] ; do
      sleep 2
      let COUNTER+=2
      echo "Waiting for mongo to initialize... ($COUNTER seconds so far)"
      grep -q 'waiting for connections on port' /var/log/mongodb.log
  done
}

echo $KEYFILE >> /home/keyfile
chown mongodb:mongodb /home/keyfile
chmod 400 /home/keyfile
echo 'Europe/London' > /etc/localtime
chmod 444 /etc/localtime
if [ $TYPE = "cfg1" ]
then
  echo "starting mongodb"
  mongod --keyFile /home/keyfile --configsvr --replSet mongors1conf --dbpath /data/db --port 27017  --bind_ip 0.0.0.0 2>&1 | tee -a /var/log/mongodb.log 1>&2 &
  retry_until
  mongo --eval 'rs.initiate({_id:"mongors1conf",configsvr:true,members:[{_id:0,host:"indexer-mongocfg1-0"}]})'
  mongo --eval 'db.getSiblingDB("admin").createUser({user:"mongors1conf-admin",pwd: "qweasd",roles:[{role:"userAdminAnyDatabase",db:"admin" },{role:"clusterAdmin",db:"admin"}],mechanisms:["SCRAM-SHA-256"]})'
  while true; do
    :
  done
elif [ $TYPE = "rs1n1" ]
then
  echo "starting mongodb"
  mongod --keyFile /home/keyfile --shardsvr --replSet mongors1 --dbpath /data/db --port 27017 --bind_ip 0.0.0.0 2>&1 | tee -a /var/log/mongodb.log 1>&2 &
  retry_until
  mongo --eval 'rs.initiate({_id:"mongors1",members:[{_id:0,host:"indexer-mongors1n1-0"}]})'
  mongo --eval 'db.getSiblingDB("admin").createUser({user:"mongors1-admin",pwd: "qweasd",roles:[{role:"userAdminAnyDatabase",db:"admin" },{role:"clusterAdmin",db:"admin"}],mechanisms:["SCRAM-SHA-256"]})'
  while true; do
    :
  done
elif [ $TYPE = "s1" ]
then
  echo "waiting for config server"
  retry_until_conf
  echo "starting mongos"
  mongos --keyFile /home/keyfile --configdb mongors1conf/indexer-mongocfg1:27017 --port 27017 --bind_ip 0.0.0.0 2>&1 | tee -a /var/log/mongodb.log 1>&2 &
  retry_until
  mongo --eval 'admin=db.getSiblingDB("admin")'
  mongo --eval 'admin.createUser({user:"mongo-admin",pwd:"qweasd",roles:[{role:"root",db:"admin"},],mechanisms:["SCRAM-SHA-256"]})'
  mongo --eval 'admin.auth("mongo-admin", "qweasd")'
  mongo --eval 'sh.addShard("mongors1/indexer-mongors1n1")'
  mongo --eval 'sh.enableSharding("iotcrawler")'
  mongo --eval 'iotcrawler=db.getSiblingDB("iotcrawler")'
  mongo --eval 'iotcrawler.createUser({user:"iotcrawler",pwd:"qweasdf",roles:[{role:"readWrite",db:"iotcrawler"},],mechanisms:["SCRAM-SHA-256"]})'

  mongo --eval 'sh.shardCollection("iotcrawler.PointMapping",{_id:"hashed"})'
  mongo --eval 'sh.shardCollection("iotcrawler.QoiMapping",{_id:"hashed"})'
  mongo --eval 'sh.shardCollection("iotcrawler.StreamMapping",{_id:"hashed"})'
  mongo --eval 'sh.shardCollection("iotcrawler.SensorMapping",{_id:"hashed"})'
  mongo --eval 'sh.shardCollection("iotcrawler.UnlocatedIotStream",{_id:"hashed"})'
  mongo --eval 'sh.shardCollection("iotcrawler.UnmatchedPoint",{_id:"hashed"})'
  mongo --eval 'sh.shardCollection("iotcrawler.UnmatchedQuality",{_id:"hashed"})'
  mongo --eval 'sh.shardCollection("iotcrawler.UnmatchedSensor",{_id:"hashed"})'
  mongo --eval 'sh.shardCollection("iotcrawler.IndexedIotStream",{countryISO:1,geoPartitionKey:1})'
  while true; do
    :
  done
else
  echo "wrong option"
fi
exit 0