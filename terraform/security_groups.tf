# 보안그룹 3개: 들어오는 요청을 "바로 앞 단계"에서 온 것만 허용한다
#   CloudFront → ALB(:80) → ECS task(:8080) → RDS(:3306)
# 규칙은 aws_vpc_security_group_ingress_rule / egress_rule 리소스로 하나씩 따로 만든다 (AWS provider 권장 방식)
# 보안그룹에 egress 규칙을 하나도 안 쓰면, Terraform이 AWS 기본 "전부 허용" egress를 지워서 나가는 것도 막힌다
# description은 AWS 규칙상 영문·숫자·일부 기호만 가능하다 (한글을 쓰면 apply가 실패한다)

# CloudFront가 원본(ALB)에 요청을 보낼 때 쓰는 IP 목록 (AWS가 관리, 자동 갱신)
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# ---------- ALB ----------
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB - HTTP from CloudFront only"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-alb-sg" }
}

# 들어오기: CloudFront IP 목록에서 오는 80번만
resource "aws_vpc_security_group_ingress_rule" "alb_from_cloudfront" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from CloudFront"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

# 나가기: ECS task의 8080으로만 (요청 전달 + 헬스체크)
resource "aws_vpc_security_group_egress_rule" "alb_to_ecs" {
  security_group_id            = aws_security_group.alb.id
  description                  = "To ECS tasks"
  referenced_security_group_id = aws_security_group.ecs.id
  ip_protocol                  = "tcp"
  from_port                    = local.backend_port
  to_port                      = local.backend_port
}

# ---------- ECS task ----------
resource "aws_security_group" "ecs" {
  name        = "${local.name_prefix}-ecs-sg"
  description = "ECS tasks - app port from ALB only"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-ecs-sg" }
}

# 들어오기: ALB 보안그룹에서 오는 8080만. Public IP가 있어도 인터넷에서 직접은 못 들어온다
resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  security_group_id            = aws_security_group.ecs.id
  description                  = "App port from ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = local.backend_port
  to_port                      = local.backend_port
}

# 나가기 1: HTTPS 443 (ECR 이미지 pull, SSM 비밀값 조회, CloudWatch 로그 전송)
resource "aws_vpc_security_group_egress_rule" "ecs_https" {
  security_group_id = aws_security_group.ecs.id
  description       = "HTTPS to AWS APIs (ECR, SSM, CloudWatch)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# 나가기 2: RDS 3306
resource "aws_vpc_security_group_egress_rule" "ecs_to_rds" {
  security_group_id            = aws_security_group.ecs.id
  description                  = "MySQL to RDS"
  referenced_security_group_id = aws_security_group.rds.id
  ip_protocol                  = "tcp"
  from_port                    = local.db_port
  to_port                      = local.db_port
}

# ---------- RDS ----------
resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS - MySQL from ECS tasks only"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-rds-sg" }
}

# 들어오기: ECS 보안그룹에서 오는 3306만. 나가기 규칙은 두지 않는다 (DB는 먼저 연결을 걸 일이 없다)
resource "aws_vpc_security_group_ingress_rule" "rds_from_ecs" {
  security_group_id            = aws_security_group.rds.id
  description                  = "MySQL from ECS tasks"
  referenced_security_group_id = aws_security_group.ecs.id
  ip_protocol                  = "tcp"
  from_port                    = local.db_port
  to_port                      = local.db_port
}
