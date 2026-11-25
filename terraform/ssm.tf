# 운영 비밀값 : JWT 시크릿, 관리자 아이디·비밀번호 (DB 비밀번호는 rds.tf)
# 경로 : /pharmlink/prod/<이름>, SecureString(기본 키 aws/ssm → 추가 KMS 요금 없음)
#
# 실제 값은 코드에도 state에도 남기지 않는다.
#   1) apply로 자리만 만든다 (값 = UNSET)
#   2) 실제 값은 CLI로 덮어쓴다
#      aws ssm put-parameter --name /pharmlink/prod/JWT_SECRET --type SecureString --overwrite --value '...'
#   3) value_wo(쓰기 전용, Terraform 1.11 이상)라서 Terraform은 이 값을 state에 저장하지 않고 다시 비교하지도 않는다
#      → 다음 apply가 UNSET으로 되돌리지 않는다.
#      일반 value를 쓰면 plan·apply 때마다 AWS에서 실제 값을 읽어 state(S3)에 저장해 버린다.
#      value_wo_version 숫자를 올릴 때만 UNSET을 다시 써 넣으므로, 이 숫자는 건드리지 않는다.
#
# 임시값 UNSET(5자)은 일부러 짧게 한다. 2)를 잊고 task를 띄우면 JWT_SECRET(32자 미만)·ADMIN_PASSWORD(8자 미만)
# 검사에 걸려 서버가 시작을 거부할 경우 -> 약한 비밀번호로 관리자 계정이 만들어지는 사고를 막는다.
#
# ECS task definition에서 쓰는 법 (ecs.tf) :
#   secrets = [{ name = "JWT_SECRET", valueFrom = aws_ssm_parameter.app["JWT_SECRET"].arn }, ...]

locals {
  ssm_prefix = "/${var.project}/${var.environment}"
}

resource "aws_ssm_parameter" "app" {
  for_each = toset(["JWT_SECRET", "ADMIN_USERNAME", "ADMIN_PASSWORD", "GEMINI_API_KEY"])

  name             = "${local.ssm_prefix}/${each.key}"
  type             = "SecureString"
  value_wo         = "UNSET"
  value_wo_version = 1
}
