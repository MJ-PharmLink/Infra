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
