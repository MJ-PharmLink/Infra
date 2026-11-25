#!/usr/bin/env bash
# 작업 시작: RDS를 켜고, 준비되면 백엔드 task를 1개로 올린다
# 사용법: AWS_PROFILE=pharmlink ./scripts/start.sh
set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-2}"
CLUSTER="${ECS_CLUSTER:-pharmlink-prod-cluster}"
SERVICE="${ECS_SERVICE:-pharmlink-prod-backend}"
DB_ID="${DB_INSTANCE_ID:-pharmlink-prod-db}"

status=$(aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$DB_ID" \
  --query 'DBInstances[0].DBInstanceStatus' --output text)
if [ "$status" = "stopped" ]; then
  echo "RDS 시작 중... ($DB_ID)"
  aws rds start-db-instance --region "$REGION" --db-instance-identifier "$DB_ID" >/dev/null
fi
echo "RDS가 available 될 때까지 기다리는 중..."
aws rds wait db-instance-available --region "$REGION" --db-instance-identifier "$DB_ID"

echo "ECS 서비스 task 1개로 올리는 중... ($SERVICE)"
aws ecs update-service --region "$REGION" --cluster "$CLUSTER" --service "$SERVICE" --desired-count 1 >/dev/null
aws ecs wait services-stable --region "$REGION" --cluster "$CLUSTER" --services "$SERVICE"
echo "켜짐: CloudFront 주소로 접속해서 확인하세요."
