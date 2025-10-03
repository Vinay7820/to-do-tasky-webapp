#!/bin/bash
set -xe

apt-get update -y
apt-get install -y gnupg curl awscli

curl -fsSL https://pgp.mongodb.com/server-5.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-archive-keyring.gpg
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-archive-keyring.gpg ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/5.0 multiverse" \
  | tee /etc/apt/sources.list.d/mongodb-org-5.0.list

apt-get update -y
apt-get install -y mongodb-org

sed -i 's/^  bindIp:.*$/  bindIp: 0.0.0.0/' /etc/mongod.conf


systemctl enable mongod
systemctl restart mongod

until mongo --eval "db.adminCommand('ping')" >/dev/null 2>&1; do
  echo "waiting for mongo to start..."
  sleep 5
done

mongo --eval 'use taskydb; db.createUser({user:"taskyuser",pwd:"taskypass",roles:[{role:"readWrite",db:"taskydb"}]})'
sed -i 's/^#security:/security:\n  authorization: enabled/' /etc/mongod.conf
systemctl restart mongod

# --- NEW: Wait for S3 bucket readiness ---
BUCKET_NAME="${project}-mongo-backups"
echo "Waiting for S3 bucket s3://$BUCKET_NAME ..."
until aws s3 ls "s3://$BUCKET_NAME" >/dev/null 2>&1; do
  sleep 5
done
echo "S3 bucket ready!"

echo "0 2 * * * root mongodump --out /tmp/mongobackup && aws s3 cp --recursive /tmp/mongobackup s3://${var.project}-mongo-backups/" >> /etc/crontab

