# 다른 파일에서 만든 값 중 GitHub Actions Variables나 스크립트에 옮겨 적을 값을 여기 모은다
output "account_id" {
  description = "AWS 계정 ID"
  value       = data.aws_caller_identity.current.account_id
}

output "name_prefix" {
  description = "리소스 이름 접두어"
  value       = local.name_prefix
}

# ---------- 네트워크 (ecs.tf, alb.tf, rds.tf에서 같은 값을 쓰고, 콘솔에서 찾을 때 참고) ----------
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet ID (ALB, ECS task)"
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  description = "Private subnet ID (RDS)"
  value       = [for s in aws_subnet.private : s.id]
}

output "security_group_ids" {
  description = "보안그룹 ID"
  value = {
    alb = aws_security_group.alb.id
    ecs = aws_security_group.ecs.id
    rds = aws_security_group.rds.id
  }
}

output "ecr_repository_name" {
  description = "Backend GitHub Actions Variables: ECR_REPOSITORY"
  value       = aws_ecr_repository.backend.name
}

output "ecr_repository_url" {
  description = "이미지 주소 (ecs.tf task definition, 수동 push)"
  value       = aws_ecr_repository.backend.repository_url
}

output "ssm_app_parameter_names" {
  description = "비밀값 파라미터 이름 (put-parameter로 실제 값 입력)"
  value       = [for p in aws_ssm_parameter.app : p.name]
}

# ---------- ALB (cdn.tf의 CloudFront origin, ecs.tf의 load_balancer 블록에서 사용) ----------
output "alb_dns_name" {
  description = "ALB DNS name (CloudFront /api/* origin)"
  value       = aws_lb.main.dns_name
}

output "alb_target_group_arn" {
  description = "Backend target group ARN (ecs.tf load_balancer)"
  value       = aws_lb_target_group.backend.arn
}

# ---------- RDS (ecs.tf task definition의 DB 접속 정보) ----------
output "db_endpoint" {
  description = "RDS address (host only)"
  value       = aws_db_instance.main.address
}

output "db_jdbc_url" {
  description = "ECS env DB_URL"
  value       = local.db_jdbc_url
}

output "db_username" {
  description = "ECS env SPRING_DATASOURCE_USERNAME"
  value       = local.db_username
}

output "db_password_parameter_arn" {
  description = "ECS secrets SPRING_DATASOURCE_PASSWORD valueFrom"
  value       = aws_ssm_parameter.db_password.arn
}

# ---------- ECS (백엔드 GitHub Actions Variables) ----------
output "ecs_cluster" {
  description = "Backend Variables : ECS_CLUSTER"
  value       = aws_ecs_cluster.main.name
}
output "ecs_service" {
  description = "Backend Variables : ECS_SERVICE"
  value       = aws_ecs_service.backend.name
}

output "ecs_task_family" {
  description = "Backend Variables : ECS_TASK_FAMILY"
  value       = aws_ecs_task_definition.backend.family
}

output "container_name" {
  description = "Backend Variables : CONTAINER_NAME"
  value       = local.backend_container_name
}

# ---------- CDN (프론트 업로드, 캐시 무효화) ----------
output "frontend_bucket_name" {
  description = "프론트 빌드 파일 업로드 버킷"
  value       = aws_s3_bucket.frontend.bucket
}

output "cloudfront_distribution_id" {
  description = "CloudFront 배포 ID (캐시 무효화)"
  value       = aws_cloudfront_distribution.main.id
}

output "site_url" {
  description = "접속 주소"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

# ---------- GitHub OIDC (각 저장소 Actions Variables : AWS_ROLE_ARN) ----------
output "github_backend_role_arn" {
  description = "Backend Variables : AWS_ROLE_ARN"
  value       = aws_iam_role.github_backend.arn
}

output "github_frontend_role_arn" {
  description = "Frontend Variables : AWS_ROLE_ARN"
  value       = aws_iam_role.github_frontend.arn
}
