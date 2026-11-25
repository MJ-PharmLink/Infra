provider "aws" {
  region = var.aws_region

  # 모든 리소스에 붙는 태그. Cost Explorer에서 Project 태그로 이 프로젝트 비용만 볼 수 있다
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
