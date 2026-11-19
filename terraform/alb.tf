# [ALB : 인터넷 요청을 받아 ECS 태스크(백엔드 컨테이너)로 나눠 주는 로드밸런서]
#
# 요청 흐름 : CloudFront(/api/*) ─80→ ALB 리스너 ─8080→ 대상 그룹 ─→ Fargate 태스크
#
# - ALB 보안그룹(alb-sg)이 CloudFront에서 오는 80번만 허용하므로 브라우저나 curl로 ALB 주소에 직접 접속하면 막힌다.
# - HTTPS는 CloudFront가 맡고, CloudFront → ALB 구간은 HTTP(80)다. (도메인·ACM 인증서를 쓰지 않는 계획)

# ---------- 1) 로드밸런서 본체 ----------
resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false         # 인터넷(CloudFront)에서 접근하는 ALB
  load_balancer_type = "application" # HTTP 경로·헤더를 보고 나눠 주는 L7 로드밸런서
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for s in aws_subnet.public : s.id] # ALB는 서로 다른 AZ 서브넷 2개 이상이 필수 (2a, 2c)

  drop_invalid_header_fields = true  # 형식이 잘못된 HTTP 헤더는 버린다 (헤더 조작 공격 방지)
  enable_deletion_protection = false # terraform destroy로 지울 수 있게 끈다

  tags = {
    Name = "${local.name_prefix}-alb"
  }
}

# ---------- 2) 대상 그룹 : 요청을 받을 백엔드 컨테이너들의 묶음 ----------
# 태스크가 뜨면 ECS 서비스(ecs.tf)가 태스크 IP를 여기에 자동으로 등록하고, 내려가면 자동으로 뺀다.
resource "aws_lb_target_group" "backend" {
  name        = "${local.name_prefix}-backend-tg"
  port        = local.backend_port # 8080 (Spring Boot)
  protocol    = "HTTP"
  target_type = "ip" # Fargate(awsvpc 네트워크)는 EC2 인스턴스가 아니라 태스크 IP로 등록해야 한다
  vpc_id      = aws_vpc.main.id

  # 배포로 옛 태스크를 내릴 때, 처리 중인 요청을 마칠 때까지 기다리는 시간 (기본 300초 → 30초로 줄여 배포를 빠르게)
  deregistration_delay = 30

  # 헬스체크 : ALB가 30초마다 GET /actuator/health 를 보내 200이면 정상, 아니면 그 태스크로 요청을 보내지 않는다
  # 백엔드 application.yaml 에서 health 하나만 노출하고, DB 연결까지 확인한다 → DB가 없으면 503(비정상)
  health_check {
    enabled             = true
    path                = local.health_check_path # /actuator/health
    port                = "traffic-port"          # 위 port(8080)와 같은 포트로 검사
    protocol            = "HTTP"
    matcher             = "200" # 200만 정상 (DOWN이면 Spring이 503을 준다)
    interval            = 30    # 30초마다 검사
    timeout             = 5     # 5초 안에 응답이 없으면 실패 1회
    healthy_threshold   = 2     # 연속 2번 성공하면 정상 (약 1분)
    unhealthy_threshold = 3     # 연속 3번 실패하면 비정상 (약 1분 30초)
  }

  tags = {
    Name = "${local.name_prefix}-backend-tg"
  }
}

# ---------- 3) 리스너 : ALB가 80번 포트로 받은 요청을 대상 그룹으로 넘긴다 ----------
# CloudFront가 /api/* 만 ALB로 보내므로 여기서는 경로를 나누지 않고 전부 백엔드로 보낸다.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  tags = {
    Name = "${local.name_prefix}-http-listener"
  }
}
