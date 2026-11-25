variable "project" {
  description = "리소스 이름 앞에 붙는 프로젝트 이름"
  type        = string
  default     = "pharmlink"
}

variable "environment" {
  description = "환경 이름"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS 리전 (서울)"
  type        = string
  default     = "ap-northeast-2"
}

variable "github_org" {
  description = "GitHub Actions OIDC 신뢰 대상 조직"
  type        = string
  default     = "MJ-PharmLink"
}

variable "backend_image_tag" {
  description = "처음 띄울 백엔드 이미지 태그 (ECR에 push한 Backend 커밋 SHA 7자리). 이후 배포는 GitHub Actions가 바꾼다"
  type        = string
  # 2일차에 push한 태그가 다르면 이 값만 그 7자리로 바꾼다 (비밀값 아님).
  default = "89b15c7"
}
variable "alert_emails" {
  description = "CloudWatch 알람 메일을 받을 주소 목록 (terraform.tfvars 에만 적는다. git에 올리지 않음)"
  type        = list(string)

  validation {
    condition     = alltrue([for e in var.alert_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "alert_emails 에는 메일 주소 형식만 넣을 수 있습니다."
  }
}
