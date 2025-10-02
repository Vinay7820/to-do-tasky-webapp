#!/usr/bin/env bash
set -euo pipefail

REGION="us-east-1"
REPO_URI=$(terraform -chdir=terraform-scripts output -raw ecr_repo_uri)
TAG="${1:-wiz-v1}"

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REPO_URI"

docker build -t tasky-app ../tasky-app
docker tag tasky-app:latest "$REPO_URI:$TAG"
docker push "$REPO_URI:$TAG"

kubectl rollout restart deployment tasky -n tasky-wiz
