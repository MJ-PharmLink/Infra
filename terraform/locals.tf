locals {
  # 리소스 이름 규칙: pharmlink-prod-<용도>
  name_prefix = "${var.project}-${var.environment}"

  backend_container_name = "backend"
  backend_port           = 8080
  health_check_path      = "/actuator/health"
  db_port                = 3306
  db_name                = "pharm_erp"

  # scripts/start.sh, stop.sh 와 GitHub Actions Variables 가 이 이름을 그대로 쓴다
  ecs_cluster_name = "${local.name_prefix}-cluster"
  ecs_service_name = "${local.name_prefix}-backend"
  db_identifier    = "${local.name_prefix}-db"
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}
