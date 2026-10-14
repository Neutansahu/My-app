# myapp: containerized deployment to AWS ECS (Fargate)

## Project layout
    server.js                      Express app with / and /health
    package.json                   Dependencies
    Dockerfile                     Multi-stage production image
    .dockerignore / .gitignore     Keep secrets and junk out of the image and repo
    .env.example                   Template for local environment variables
    docker-compose.yml             Local run
    scripts/build-and-push.sh      Build linux/amd64 image and push to ECR
    infra/ecs/task-definition.json ECS task definition template
    infra/ecs/deploy-service.sh    Register task revision and roll the ECS service
    .github/workflows/deploy.yml   Optional CI/CD on push to main

## 1. Prerequisites
- AWS account and an IAM user/role with ECR, ECS, ELB, IAM (read), CloudWatch Logs permissions
- AWS CLI v2: `aws configure` (region e.g. ap-south-1)
- Docker with Buildx (Docker Desktop includes it)
- Node.js 20 (only needed to generate the lock file)

## 2. Run locally
```bash
npm install                       # creates package-lock.json (commit it)
cp .env.example .env
docker compose up --build
curl http://localhost:8080/health # {"status":"ok"}
```

## 3. Create the AWS infrastructure (one time, console or CLI)
1. **ECR repository** (the deploy script creates it, or create it manually):
   `aws ecr create-repository --repository-name myapp --image-scanning-configuration scanOnPush=true --region ap-south-1`
2. **CloudWatch log group:**
   `aws logs create-log-group --log-group-name /ecs/myapp --region ap-south-1`
3. **ECS task execution role** `ecsTaskExecutionRole` with the managed policy `AmazonECSTaskExecutionRolePolicy`. Note its ARN and replace `ACCOUNT_ID` in the task definition if you're not using the placeholder substitution in the script.
4. **ECS cluster:** Console > ECS > Create cluster > name `myapp-cluster`, infrastructure AWS Fargate.
5. **VPC and networking:** use the default VPC with at least two public subnets, or a VPC you already have.
6. **Security groups:**
   - ALB SG: inbound TCP 80 (and 443 if you add TLS) from 0.0.0.0/0
   - Service SG: inbound TCP 8080 from the ALB SG only
7. **Application Load Balancer:** internet-facing, listener on port 80, target group type IP, port 8080, health check path `/health`, success codes 200.
8. **ECS service:** in `myapp-cluster`, launch type Fargate, family `myapp`, service name `myapp-service`, desired tasks 2, attach to the target group, subnets from step 5, service SG from step 6. Wait for the first deployment to finish. The first task definition revision can use any image you've already pushed; the deploy script replaces it on every run.

## 4. Build and push the image
```bash
export AWS_REGION=ap-south-1
./scripts/build-and-push.sh
export IMAGE=$(cat .last-image)
```

## 5. Deploy the new version to ECS
```bash
export CLUSTER=myapp-cluster
export SERVICE=myapp-service
./infra/ecs/deploy-service.sh
```
This registers a new task definition revision pointing at `$IMAGE`, updates the service, and waits until it's stable.

## 6. Verify
```bash
ALB_DNS=$(aws elbv2 describe-load-balancers --names myapp-alb \
  --query 'LoadBalancers[0].DNSName' --output text --region ap-south-1)
curl http://$ALB_DNS/health
```
Logs: CloudWatch > Log groups > `/ecs/myapp`.

## 7. Continuous deployment (optional)
1. In IAM, create an OIDC identity provider for `token.actions.githubusercontent.com` and a role that trusts your GitHub repo's `main` branch, with ECR push and ECS update permissions.
2. In GitHub repo settings > Secrets, add `AWS_ROLE_ARN` with that role's ARN.
3. Push to `main`. The workflow builds, pushes, and deploys.

## 8. Roll back
Find the previous task definition revision and redeploy it:
```bash
aws ecs list-task-definitions --family-prefix myapp --sort DESC --max-items 5
aws ecs update-service --cluster myapp-cluster --service myapp-service \
  --task-definition myapp:<previous-revision> --region ap-south-1
```

## 9. Secrets
Don't put secrets in the image or in `task-definition.json`. Store them in SSM Parameter Store (SecureString) or Secrets Manager, and add them to the container definition under `"secrets"` with `valueFrom` set to the parameter ARN. The task execution role needs `ssm:GetParameters` (or `secretsmanager:GetSecretValue`) for those resources.

## 10. Clean up
Delete the ECS service (scale to 0 first), cluster, ALB, target group, ECR images, and log group. Idle load balancers cost money.
