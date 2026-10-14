#!/usr/bin/env bash
# Builds the image for linux/amd64 (what Fargate runs) and pushes it to ECR.
# Usage: AWS_REGION=ap-south-1 ./scripts/build-and-push.sh
set -euo pipefail

: "${AWS_REGION:?set AWS_REGION, e.g. ap-south-1}"
APP_NAME="${APP_NAME:-myapp}"
TAG="${TAG:-$(git rev-parse --short HEAD 2>/dev/null || date +%Y%m%d%H%M%S)}"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
IMAGE="$REGISTRY/$APP_NAME:$TAG"

# Create the repository if it doesn't exist yet
if ! aws ecr describe-repositories --repository-names "$APP_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws ecr create-repository --repository-name "$APP_NAME" \
    --image-scanning-configuration scanOnPush=true --region "$AWS_REGION" >/dev/null
  echo "Created ECR repository $APP_NAME"
fi

aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$REGISTRY"

docker buildx build --platform linux/amd64 -t "$IMAGE" --push .

echo "Pushed: $IMAGE"
echo "$IMAGE" > .last-image
