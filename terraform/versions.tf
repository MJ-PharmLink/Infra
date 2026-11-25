terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # 상태 파일은 콘솔에서 만든 S3 버킷에 저장한다
  # use_lockfile: 두 사람이 동시에 apply 하지 못하게 S3에 잠금 파일을 만든다
  backend "s3" {
    bucket       = "pharmlink-tfstate-906982597865"
    key          = "prod/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
