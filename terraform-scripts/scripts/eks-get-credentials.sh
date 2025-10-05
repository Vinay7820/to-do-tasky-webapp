#!/usr/bin/env bash
set -euo pipefail

# Usage: eks-get-credentials.sh <cluster-name> <region> [timeout_seconds]
CLUSTER_NAME="${1:?cluster name required}"
REGION="${2:?region required}"
TIMEOUT="${3:-600}"   # default 10 minutes
INTERVAL=10
ELAPSED=0

# wait until EKS cluster becomes ACTIVE
while true; do
  STATUS=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query "cluster.status" --output text 2>/dev/null || true)
  if [ "$STATUS" = "ACTIVE" ]; then
    break
  fi
  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    echo "{\"error\":\"timeout waiting for cluster to become ACTIVE\"}"
    exit 1
  fi
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done

# get endpoint and CA data
ENDPOINT=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query "cluster.endpoint" --output text)
CA_DATA=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query "cluster.certificateAuthority.data" --output text)

# get token (aws cli v2)
TOKEN_JSON=$(aws eks get-token --cluster-name "$CLUSTER_NAME" --region "$REGION" --output json)
TOKEN=$(echo "$TOKEN_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['status']['token'])")

# output JSON in format Terraform external data expects
python3 - <<PY
import json, sys
print(json.dumps({
  "endpoint": "$ENDPOINT",
  "ca": "$CA_DATA",
  "token": "$TOKEN"
}))
PY

