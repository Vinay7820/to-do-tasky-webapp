#!/bin/bash
set -xe

##############################################
# MongoDB EC2 Initialization Script
#  - Installs MongoDB 5.0
#  - Enables remote access & authentication
#  - Configures cron-based S3 backups
##############################################

project="${project}"
bucket_suffix="${bucket_suffix}"
BUCKET_NAME="${project}-mongo-backups-${bucket_suffix}"
LOG_FILE="/var/log/mongo_backup.log"

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

# --- Create MongoDB user for the application ---
mongo --eval 'use taskydb; db.createUser({user:"taskyuser",pwd:"taskypass",roles:[{role:"readWrite",db:"taskydb"}]})'


# --- Enable MongoDB authentication ---
if grep -q "authorization:" /etc/mongod.conf; then
  sed -i 's/authorization:.*/authorization: enabled/' /etc/mongod.conf
elif grep -q "^#security:" /etc/mongod.conf; then
  sed -i 's/^#security:.*/security:\n  authorization: enabled/' /etc/mongod.conf
elif grep -q "^security:" /etc/mongod.conf; then
  sed -i '/^security:/a\  authorization: enabled' /etc/mongod.conf
else
  echo -e "\nsecurity:\n  authorization: enabled" >> /etc/mongod.conf
fi

sudo systemctl restart mongod

touch "$LOG_FILE"
chmod 644 "$LOG_FILE"
echo "[$(date)] Mongo backup log initialized." >> "$LOG_FILE"

# --- Schedule daily Mongo backups at 5 PM IST (11:30 UTC) ---
cat <<EOF >> /etc/cron.d/mongo_backup
30 11 * * * root timestamp=\$(date +\\%Y-\\%m-\\%d_\\%H-\\%M-\\%S); \
mongodump --out /tmp/mongobackup_\$timestamp >> $LOG_FILE 2>&1 && \
aws s3 cp --recursive /tmp/mongobackup_\$timestamp s3://$bucket_name/backup_\$timestamp/ >> $LOG_FILE 2>&1 && \
echo "[\$(date)] Backup completed successfully." >> $LOG_FILE || \
echo "[\$(date)] Backup FAILED." >> $LOG_FILE
EOF

systemctl restart cron
echo "Mongo backup cron job configured for bucket s3://$bucket_name"

