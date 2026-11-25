# [CDN : CloudFront 주소 하나로 화면(S3)과 API(ALB)를 같이 제공]
#
# /      → S3 (프론트 빌드 파일)
# /api/* → ALB → ECS
# 도메인이 없어서 CloudFront 기본 인증서로 HTTPS를 쓴다.

# ---------- 1) S3 버킷 : 프론트 빌드 파일 (비공개_외부접근차단) ----------
resource "aws_s3_bucket" "frontend" {
  bucket        = "${local.name_prefix}-frontend-${data.aws_caller_identity.current.account_id}" # 버킷 이름은 유일해야 함
  force_destroy = true                                                                           # destroy 때 파일이 남아 있어도 삭제

  tags = {
    Name = "${local.name_prefix}-frontend"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ACL은 쓰지 않고 버킷 정책으로만 권한을 준다
resource "aws_s3_bucket_ownership_controls" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ---------- 2) OAC : CloudFront가 서명한 요청만 S3가 받는다 ----------
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${local.name_prefix}-frontend-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ---------- 3) 캐시·전달 정책 ----------
# 화면 : 오래 캐시 (index.html은 업로드할 때 no-cache)
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

# API : 캐시 안 함
data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

# API 요청은 Host, Origin만 빼고 ALB로 넘긴다
# - Host : ALB 주소로 접속해야 한다
# - Origin : 그대로 넘기면 백엔드가 CORS 요청으로 보고 POST(로그인)를 403으로 막는다. 같은 주소라 CORS는 필요 없다
resource "aws_cloudfront_origin_request_policy" "api" {
  name    = "${local.name_prefix}-api"
  comment = "all viewer headers except Host, Origin"

  cookies_config {
    cookie_behavior = "all"
  }

  headers_config {
    header_behavior = "allExcept"
    headers {
      items = ["Host", "Origin"]
    }
  }

  query_strings_config {
    query_string_behavior = "all"
  }
}

# ---------- 4) CloudFront 배포 ----------
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  comment             = "${local.name_prefix} frontend + api"
  default_root_object = "index.html"
  price_class         = "PriceClass_200" # 한국 포함 (100은 북미, 유럽만)
  http_version        = "http2and3"

  origin {
    origin_id                = "s3-frontend"
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  origin {
    origin_id   = "alb-backend"
    domain_name = aws_lb.main.dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # ALB 리스너가 80만 연다
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # 화면 : S3
  default_cache_behavior {
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimized.id
  }

  # API : ALB
  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = "alb-backend"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = true
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.api.id
  }

  # 404 → index.html 설정은 넣지 않는다 (라우터가 없고, 넣으면 API의 404도 index.html로 바뀐다)

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "${local.name_prefix}-cdn"
  }
}

# ---------- 5) 버킷 정책 : 이 CloudFront 배포만 읽을 수 있다 ----------
data "aws_iam_policy_document" "frontend_bucket" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.main.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket     = aws_s3_bucket.frontend.id
  policy     = data.aws_iam_policy_document.frontend_bucket.json
  depends_on = [aws_s3_bucket_public_access_block.frontend]
}