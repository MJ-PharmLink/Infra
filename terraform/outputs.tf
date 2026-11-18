# 다른 파일에서 만든 값 중 GitHub Actions Variables나 스크립트에 옮겨 적을 값을 여기 모은다
output "account_id" {
  description = "AWS 계정 ID"
  value       = data.aws_caller_identity.current.account_id
}

output "name_prefix" {
  description = "리소스 이름 접두어"
  value       = local.name_prefix
}
