#!/usr/bin/env bash
# 작업 끝: 백엔드 task를 0개로 내리고 RDS를 중지한다 (ALB·CloudFront·S3는 그대로 둔다)
# 사용법: AWS_PROFILE=pharmlink ./scripts/stop.sh
# 주의: 중지된 RDS는 7일이 지나면 AWS가 자동으로 다시 켠다
set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-2}"
CLUSTER="${ECS_CLUSTER:-pharmlink-prod-cluster}"
SERVICE="${ECS_SERVICE:-pharmlink-prod-backend}"
DB_ID="${DB_INSTANCE_ID:-pharmlink-prod-db}"

echo "ECS 서비스 task 0개로 내리는 중... ($SERVICE)"
aws ecs update-service --region "$REGION" --cluster "$CLUSTER" --service "$SERVICE" --desired-count 0 >/dev/null
aws ecs wait services-stable --region "$REGION" --cluster "$CLUSTER" --services "$SERVICE"

status=$(aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$DB_ID" \
  --query 'DBInstances[0].DBInstanceStatus' --output text)
if [ "$status" = "available" ]; then
  echo "RDS 중지 중... ($DB_ID)"
  aws rds stop-db-instance --region "$REGION" --db-instance-identifier "$DB_ID" >/dev/null
else
  echo "RDS 상태가 '$status'라서 중지 요청을 건너뜁니다."
fi
echo "꺼짐: 다음 작업 때 ./scripts/start.sh"
