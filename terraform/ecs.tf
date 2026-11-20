# 보안그룹 규칙(ALB→ECS 8080, ECS→443·RDS 3306)은 security_groups.tf에 있다.

locals {
  ecs_subnet_ids = [for s in aws_subnet.public : s.id]
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${local.name_prefix}-backend"
  retention_in_days = 7
}

resource "aws_ecs_cluster" "main" {
  name = local.ecs_cluster_name

  setting {
    name  = "containerInsights"
    value = "disabled" # 추가 요금 방지
  }
}

resource "aws_ecs_task_definition" "backend" {
  family                   = "${local.name_prefix}-backend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512  # 0.5 vCPU
  memory                   = 1024 # 1GB (Dockerfile MaxRAMPercentage=75 → 힙 약 768MB)
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64" # 이미지는 --platform linux/amd64 로 빌드
  }

  container_definitions = jsonencode([
    {
      name      = local.backend_container_name
      image     = "${aws_ecr_repository.backend.repository_url}:${var.backend_image_tag}"
      essential = true

      portMappings = [
        { containerPort = local.backend_port, protocol = "tcp" }
      ]

      # 비밀이 아닌 운영 값
      environment = [
        { name = "SPRING_PROFILES_ACTIVE", value = "prod" },
        { name = "TZ", value = "Asia/Seoul" },
        # RDS 접속 정보 (rds.tf). 비밀번호는 아래 secrets에서 SSM으로 넣는다
        { name = "DB_URL", value = local.db_jdbc_url },
        { name = "SPRING_DATASOURCE_USERNAME", value = aws_db_instance.main.username },
      ]

      # Parameter Store → 환경변수 (task 시작 때 주입)
      secrets = [
        { name = "JWT_SECRET", valueFrom = aws_ssm_parameter.app["JWT_SECRET"].arn },
        { name = "ADMIN_USERNAME", valueFrom = aws_ssm_parameter.app["ADMIN_USERNAME"].arn },
        { name = "ADMIN_PASSWORD", valueFrom = aws_ssm_parameter.app["ADMIN_PASSWORD"].arn },
        { name = "SPRING_DATASOURCE_PASSWORD", valueFrom = aws_ssm_parameter.db_password.arn }, # rds.tf가 만든 DB 비밀번호
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.backend.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "backend"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "backend" {
  name            = local.ecs_service_name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  launch_type     = "FARGATE"

  # 처음엔 0 (RDS가 없으면 DB 연결 실패로 재시작만 반복)
  # 이후 켜고 끄기는 scripts/start.sh·stop.sh가 CLI로 바꾸고, 아래 ignore_changes로 apply가 되돌리지 않는다.
  desired_count = 0

  # Spring Boot 기동(0.5 vCPU에서 약 30~60초) 동안 ALB 헬스체크 실패로 죽이지 않게
  health_check_grace_period_seconds = 120

  # 새 task가 정상이 된 뒤 옛 task를 내린다. 실패하면 직전 버전으로 자동 롤백
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = local.ecs_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true # NAT가 없어서 필수. 빠지면 ECR 이미지를 못 받아 task가 안 뜸
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn # (다)
    container_name   = local.backend_container_name
    container_port   = local.backend_port
  }

  depends_on = [aws_lb_listener.http]

  lifecycle {
    ignore_changes = [desired_count]
  }
}
