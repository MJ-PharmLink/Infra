# [CloudTrail : "누가, 언제, 무엇을 바꿨는지" AWS 작업 기록을 S3에 남긴다]
#
# 콘솔 클릭, CLI, Terraform, GitHub Actions 배포 모두 AWS API 호출이라 전부 기록된다.
# 콘솔의 Event history 는 90일만 보여주고 지워지므로, 트레일(trail)로 S3에 파일로 따로 보관한다.

locals {
  cloudtrail_name = "${local.name_prefix}-trail"
  # 트레일 ARN을 미리 계산 (버킷 정책 ↔ 트레일이 서로를 기다리는 순환을 피하려고)
  cloudtrail_arn = "arn:aws:cloudtrail:${var.aws_region}:${data.aws_caller_identity.current.account_id}:trail/${local.cloudtrail_name}"
}

# ---------- 1) 기록 보관용 S3 버킷 (비공개) ----------
resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${local.name_prefix}-cloudtrail-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # 12/3 이후 destroy 때 기록 파일이 남아 있어도 삭제
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# 90일 지난 기록 파일은 자동 삭제 (저장 비용이 계속 쌓이지 않게)
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    id     = "expire-90-days"
    status = "Enabled"
    filter {}
    expiration {
      days = 90
    }
  }
}

# ---------- 2) 버킷 정책 : 우리 트레일만 이 버킷에 파일을 쓸 수 있다 ----------
data "aws_iam_policy_document" "cloudtrail_bucket" {
  # CloudTrail이 처음에 "이 버킷에 써도 되나?" 확인할 때 쓰는 권한
  statement {
    sid       = "CloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.cloudtrail_arn]
    }
  }

  # 기록 파일 쓰기 : AWSLogs/<계정번호>/ 아래에만
  statement {
    sid       = "CloudTrailWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.cloudtrail_arn] # 다른 계정·다른 트레일은 이 버킷에 못 쓴다
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.cloudtrail]
}

# ---------- 3) 트레일 ----------
resource "aws_cloudtrail" "main" {
  name           = local.cloudtrail_name
  s3_bucket_name = aws_s3_bucket.cloudtrail.id

  is_multi_region_trail         = true # 서울 말고 다른 리전에서 누가 뭘 만들어도 기록
  include_global_service_events = true # IAM·CloudFront처럼 리전이 없는 서비스도 기록
  enable_log_file_validation    = true # 기록 파일이 나중에 고쳐지지 않았는지 검증할 수 있게 해시를 남긴다

  # event_selector 를 안 쓰면 기본값 = 관리 이벤트 전체(읽기+쓰기)만 기록

  depends_on = [aws_s3_bucket_policy.cloudtrail] # 버킷 정책이 먼저 있어야 트레일 생성이 성공한다
}
