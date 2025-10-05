#!/bin/bash
set -euo pipefail

# =========================================================
# MongoDB → S3 Backup Verification Script
# =========================================================
# ✅ Triggers manual mongodump
# ✅ Uploads to S3 bucket defined in system
# ✅ Confirms upload success
# ✅ Tests if bucket and files are publicly accessible
# =========================================================

LOG_FILE="/tmp/mongo_s3_backup_verification.log"
echo "🔍 Starting MongoDB → S3 backup verification..." | tee "$LOG_FILE"
echo "---------------------------------------------------" | tee -a "$LOG_FILE"

# --- Identify backup bucket name from Terraform naming convention ---
BUCKET_NAME=$(aws s3 ls | grep mongo-backups | awk '{print $3}' | head -n1 || true)

if [[ -z "$BUCKET_NAME" ]]; then
  echo "❌ Could not detect backup bucket automatically. Please check AWS S3." | tee -a "$LOG_FILE"
  exit 1
fi

echo "🪣 Detected backup bucket: $BUCKET_NAME" | tee -a "$LOG_FILE"

# --- Create a new timestamped backup ---
timestamp=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_DIR="/tmp/mongobackup_$timestamp"
echo "📦 Creating MongoDB backup: $BACKUP_DIR" | tee -a "$LOG_FILE"

if ! mongodump --authenticationDatabase taskydb -u taskyuser -p taskypass --out "$BACKUP_DIR" >> "$LOG_FILE" 2>&1; then
  echo "❌ MongoDB dump failed!" | tee -a "$LOG_FILE"
  exit 1
fi
echo "✅ MongoDB dump completed." | tee -a "$LOG_FILE"

# --- Upload to S3 ---
echo "☁️ Uploading to s3://$BUCKET_NAME/backup_$timestamp/" | tee -a "$LOG_FILE"
if aws s3 cp --recursive "$BACKUP_DIR" "s3://$BUCKET_NAME/backup_$timestamp/" >> "$LOG_FILE" 2>&1; then
  echo "✅ Upload successful!" | tee -a "$LOG_FILE"
else
  echo "❌ Upload to S3 failed!" | tee -a "$LOG_FILE"
  exit 1
fi

# --- Verify files exist in S3 ---
echo "🔍 Verifying backup presence in S3..." | tee -a "$LOG_FILE"
S3_FILE_COUNT=$(aws s3 ls "s3://$BUCKET_NAME/backup_$timestamp/" --recursive | wc -l)
if [[ "$S3_FILE_COUNT" -gt 0 ]]; then
  echo "✅ Backup verified — $S3_FILE_COUNT files found in S3." | tee -a "$LOG_FILE"
else
  echo "❌ No files found in S3 backup folder." | tee -a "$LOG_FILE"
  exit 1
fi

# --- Check if bucket is publicly listable ---
echo "🌐 Checking public list access..." | tee -a "$LOG_FILE"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://$BUCKET_NAME.s3.amazonaws.com/")
if [[ "$HTTP_STATUS" == "200" ]]; then
  echo "✅ Public list access is ENABLED." | tee -a "$LOG_FILE"
else
  echo "❌ Public list access is DISABLED (HTTP $HTTP_STATUS)." | tee -a "$LOG_FILE"
fi

# --- Check if a file is publicly readable ---
FIRST_FILE=$(aws s3 ls "s3://$BUCKET_NAME/backup_$timestamp/" --recursive | awk '{print $4}' | head -n1)
if [[ -n "$FIRST_FILE" ]]; then
  FILE_URL="https://$BUCKET_NAME.s3.amazonaws.com/$FIRST_FILE"
  echo "🌍 Testing public read for: $FILE_URL" | tee -a "$LOG_FILE"
  FILE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$FILE_URL")
  if [[ "$FILE_STATUS" == "200" ]]; then
    echo "✅ File is publicly readable." | tee -a "$LOG_FILE"
  else
    echo "❌ File is NOT publicly readable (HTTP $FILE_STATUS)." | tee -a "$LOG_FILE"
  fi
else
  echo "⚠️ No file found to test public read access." | tee -a "$LOG_FILE"
fi

echo "---------------------------------------------------" | tee -a "$LOG_FILE"
echo "🎯 MongoDB → S3 backup verification COMPLETED" | tee -a "$LOG_FILE"
echo "📄 Full log available at: $LOG_FILE"
