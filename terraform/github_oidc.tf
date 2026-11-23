# 흐름
#   1) 워크플로가 GitHub에게 "나는 MJ-PharmLink/Backend 저장소의 main 브랜치 작업이다"라는 신분증(OIDC 토큰)을 받는다
#   2) 그 신분증을 AWS STS에 내밀고, 아래 역할(role)을 1시간짜리 임시 자격 증명으로 받는다
#   3) 역할에 붙은 권한만큼만 AWS를 쓴다 → GitHub Secrets에 장기 키를 저장하지 않는다
#
# 역할은 저장소별로 나눈다 (최소 권한)
#   - 백엔드 역할 : ECR 이미지 push + ECS 새 버전 배포만
#   - 프론트 역할 : S3 업로드 + CloudFront 캐시 무효화만
# 둘 다 main 브랜치에서 돈 워크플로만 쓸 수 있다 (PR, 다른 브랜치, 다른 저장소는 거절)

# ---------- 1) OIDC 공급자 : "GitHub가 발급한 신분증을 믿는다" (계정에 1개) ----------
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"] # aws-actions/configure-aws-credentials가 쓰는 대상(aud)
}

locals {
  github_oidc_host = "token.actions.githubusercontent.com"
}

# ---------- 2) 신뢰 정책 : 누가 역할을 빌릴 수 있는가 (저장소·브랜치로 제한) ----------
data "aws_iam_policy_document" "github_assume" {
  for_each = {
    backend  = "Backend"
    frontend = "Frontend"
  }

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # sub = "repo:<조직>/<저장소>:ref:refs/heads/main" → 이 저장소의 main 브랜치에서 돈 워크플로만 허용
    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:sub"
      values   = ["repo:${var.github_org}/${each.value}:ref:refs/heads/main"]
    }
  }
}

# ---------- 3) 백엔드 배포 역할 ----------
resource "aws_iam_role" "github_backend" {
  name                 = "${local.name_prefix}-github-backend"
  assume_role_policy   = data.aws_iam_policy_document.github_assume["backend"].json
  max_session_duration = 3600 # 1시간
}

data "aws_iam_policy_document" "github_backend" {
  # ECR 로그인 (리소스를 지정할 수 없는 권한)
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # 백엔드 이미지 저장소에만 push
  statement {
    sid = "EcrPushBackend"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:DescribeImages",
    ]
    resources = [aws_ecr_repository.backend.arn]
  }

  # task definition 읽기·등록 (AWS가 리소스 지정을 지원하지 않는 권한)
  statement {
    sid       = "EcsTaskDefinition"
    actions   = ["ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"]
    resources = ["*"]
  }

  # 백엔드 서비스에만 새 버전 배포·상태 조회
  statement {
    sid       = "EcsDeployBackendService"
    actions   = ["ecs:UpdateService", "ecs:DescribeServices"]
    resources = [aws_ecs_service.backend.id] # 서비스 ARN
  }

  # 새 task definition에 실행 역할·태스크 역할을 붙일 수 있게 (ECS에만 넘기도록 제한)
  statement {
    sid       = "PassEcsRoles"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.ecs_execution.arn, aws_iam_role.ecs_task.arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "github_backend" {
  name   = "deploy-backend"
  role   = aws_iam_role.github_backend.id
  policy = data.aws_iam_policy_document.github_backend.json
}

# ---------- 4) 프론트 배포 역할 ----------
resource "aws_iam_role" "github_frontend" {
  name                 = "${local.name_prefix}-github-frontend"
  assume_role_policy   = data.aws_iam_policy_document.github_assume["frontend"].json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "github_frontend" {
  # aws s3 sync --delete 는 버킷 목록 조회가 필요하다
  statement {
    sid       = "ListFrontendBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.frontend.arn]
  }

  # 프론트 버킷 안의 파일만 올리기·지우기
  statement {
    sid       = "WriteFrontendObjects"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]
  }

  # 이 CloudFront 배포의 캐시만 비우기
  statement {
    sid       = "InvalidateCloudFront"
    actions   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]
    resources = [aws_cloudfront_distribution.main.arn]
  }
}

resource "aws_iam_role_policy" "github_frontend" {
  name   = "deploy-frontend"
  role   = aws_iam_role.github_frontend.id
  policy = data.aws_iam_policy_document.github_frontend.json
}
