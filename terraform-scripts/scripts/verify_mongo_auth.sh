#!/bin/bash
# ==========================================================
# MongoDB Authentication Verification Script
# ----------------------------------------------------------
# Verifies:
#   ✅ MongoDB authorization is enabled
#   ✅ Unauthenticated access is blocked
#   ✅ Authenticated user can connect and write
#
# Logs full output to /tmp/mongo_auth_verification.log
# ==========================================================

LOG_FILE="/tmp/mongo_auth_verification.log"
MONGO_USER="taskyuser"
MONGO_PASS="taskypass"
MONGO_DB="taskydb"

# Reset log file
echo "" > "$LOG_FILE"

log() {
  echo -e "$1" | tee -a "$LOG_FILE"
}

log "🔍 Starting MongoDB authentication verification..."
log "---------------------------------------------------"

overall_pass=true

# ==========================================================
# Step 1 — Check if authorization is enabled
# ==========================================================
if grep -qE "^security:" /etc/mongod.conf && grep -q "authorization: enabled" /etc/mongod.conf; then
  log "✅ MongoDB authorization is ENABLED in /etc/mongod.conf"
else
  log "❌ MongoDB authorization NOT enabled — authentication bypassed."
  overall_pass=false
fi

# ==========================================================
# Step 2 — Test unauthenticated connection
# ==========================================================
log ""
log "🧩 Testing connection WITHOUT authentication..."
UNAUTH_CONN=$(mongo --quiet --eval "db.runCommand({ connectionStatus: 1 })" 2>&1)

if echo "$UNAUTH_CONN" | grep -q "authenticatedUsers" && ! echo "$UNAUTH_CONN" | grep -q "taskyuser"; then
  log "✅ Unauthenticated connection is limited (no users logged in)."
else
  log "❌ Unauthenticated connection unexpectedly shows logged-in users!"
  overall_pass=false
fi

# ==========================================================
# Step 3 — Test unauthenticated write (should fail)
# ==========================================================
log ""
log "🧪 Testing READ and WRITE access WITHOUT authentication..."
WRITE_RESULT=$(mongo --quiet --eval 'db.tasky_unauthed.insertOne({hello:"world"})' 2>&1)

if echo "$WRITE_RESULT" | grep -Eqi "not authorized|requires authentication"; then
  log "✅ Unauthenticated write was correctly blocked (auth enforced)."
else
  log "❌ Unexpected response — unauthenticated write might have succeeded:"
  log "$WRITE_RESULT"
  overall_pass=false
fi

# ==========================================================
# Step 4 — Test authenticated connection and write
# ==========================================================
log ""
log "🔐 Testing AUTHENTICATED connection and write..."
AUTH_WRITE_RESULT=$(mongo -u "$MONGO_USER" -p "$MONGO_PASS" --authenticationDatabase "$MONGO_DB" --quiet --eval 'db.tasky.insertOne({hello:"secure world"})' "$MONGO_DB" 2>&1)

if echo "$AUTH_WRITE_RESULT" | grep -q "acknowledged"; then
  log "✅ Authenticated write succeeded."
else
  log "❌ Authenticated write failed:"
  log "$AUTH_WRITE_RESULT"
  overall_pass=false
fi

# ==========================================================
# Step 5 — Check authenticated session status
# ==========================================================
log ""
log "📊 Checking authenticated connection status..."
AUTH_STATUS=$(mongo -u "$MONGO_USER" -p "$MONGO_PASS" --authenticationDatabase "$MONGO_DB" --quiet --eval "db.runCommand({ connectionStatus: 1 })" 2>&1)

if echo "$AUTH_STATUS" | grep -q "$MONGO_USER"; then
  log "✅ Authenticated session confirmed for user '$MONGO_USER'"
else
  log "❌ Could not confirm authenticated session for '$MONGO_USER'"
  overall_pass=false
fi

# ==========================================================
# Step 6 — Final result
# ==========================================================
log ""
log "---------------------------------------------------"
if [ "$overall_pass" = true ]; then
  log "🎉 MongoDB authentication verification SUCCESS ✅"
else
  log "⚠️ MongoDB authentication verification COMPLETED with ISSUES ❌"
fi
log "---------------------------------------------------"
log "📄 Full log available at: $LOG_FILE"
