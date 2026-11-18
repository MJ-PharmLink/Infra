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
