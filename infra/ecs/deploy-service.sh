#!/usr/bin/env bash
# Registers a new task definition revision with the given image and rolls the ECS service.
# Usage: AWS_REGION=... CLUSTER=... SERVICE=... IMAGE=<full image URI> ./infra/ecs/deploy-service.sh
set -euo pipefail

: "${AWS_REGION:?set AWS_REGION}"
: "${CLUSTER:?set CLUSTER}"
: "${SERVICE:?set SERVICE}"
: "${IMAGE:?set IMAGE to the full ECR image URI}"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
TMP="$(mktemp)"

sed -e "s|ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/myapp:latest|$IMAGE|" \
    -e "s|ACCOUNT_ID|$ACCOUNT_ID|g" \
    -e "s|REGION|$AWS_REGION|g" \
    infra/ecs/task-definition.json > "$TMP"

TASK_DEF_ARN="$(aws ecs register-task-definition \
  --cli-input-json "file://$TMP" --region "$AWS_REGION" \
  --query 'taskDefinition.taskDefinitionArn' --output text)"

aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" \
  --task-definition "$TASK_DEF_ARN" --force-new-deployment \
  --region "$AWS_REGION" >/dev/null

echo "Waiting for service to become stable..."
aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE" --region "$AWS_REGION"
echo "Deployed $TASK_DEF_ARN"
rm -f "$TMP"
