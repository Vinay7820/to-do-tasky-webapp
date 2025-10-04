#!/usr/bin/env bash
set -euo pipefail

REGION="us-east-1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_URI=$(terraform -chdir="$SCRIPT_DIR" output -raw ecr_repo_uri)
TAG="${1:-wiz-v1}"

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REPO_URI"

#docker build -t tasky-app ../tasky-app
#docker tag tasky-app:latest "$REPO_URI:$TAG"
#docker push "$REPO_URI:$TAG"

docker buildx create --use || true
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t "$REPO_URI:$TAG" \
  ../tasky-app \
  --push \
  --provenance=false
  
kubectl rollout restart deployment tasky -n tasky-wiz
