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
# mongo --eval 'use taskydb; db.createUser({user:"taskyuser",pwd:"taskypass",roles:[{role:"readWrite",db:"taskydb"}]})'

# --- Create MongoDB user for the application (only if not exists) ---
mongo --eval 'db = db.getSiblingDB("taskydb"); if (!db.getUser("taskyuser")) { db.createUser({user:"taskyuser",pwd:"taskypass",roles:[{role:"readWrite",db:"taskydb"}]}) }'


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

# --- Restart MongoDB service safely ---
echo "Restarting MongoDB with authentication enabled..."
if command -v systemctl >/dev/null 2>&1; then
  # Ensure systemd is fully initialized
  sleep 5
  systemctl daemon-reexec
  systemctl restart mongod || {
    echo "⚠️ systemctl restart failed — trying fallback..."
    sudo service mongod restart || echo "❌ Both restart methods failed."
  }
else
  echo "systemctl not available — using service fallback"
  sudo service mongod restart || echo "❌ MongoDB restart failed via service command."
fi

# --- Verify MongoDB is running and accepting connections ---
if pgrep mongod >/dev/null 2>&1; then
  echo "✅ MongoDB is running after restart."
else
  echo "❌ MongoDB did not start successfully. Check logs in /var/log/mongodb/mongod.log"
fi

touch "$LOG_FILE"
chmod 644 "$LOG_FILE"
echo "[$(date)] Mongo backup log initialized." >> "$LOG_FILE"

# --- Schedule daily Mongo backups at 5 PM IST (11:30 UTC) ---
sudo tee /etc/cron.d/mongo_backup > /dev/null <<EOF
30 11 * * * root timestamp=\$(date +\\%Y-\\%m-\\%d_\\%H-\\%M-\\%S); \
mongodump --out /tmp/mongobackup_\$timestamp >> $LOG_FILE 2>&1 && \
aws s3 cp --recursive /tmp/mongobackup_\$timestamp s3://$BUCKET_NAME/backup_\$timestamp/ >> $LOG_FILE 2>&1 && \
echo "[\$(date)] Backup completed successfully." >> $LOG_FILE || \
echo "[\$(date)] Backup FAILED." >> $LOG_FILE
EOF

sudo chmod 644 /etc/cron.d/mongo_backup
sudo systemctl restart cron
echo "✅ Mongo backup cron job configured for bucket s3://$BUCKET_NAME"

