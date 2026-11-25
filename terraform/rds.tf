# [RDS : 백엔드가 쓰는 MySQL 데이터베이스]
#
# - MySQL 8.4, db.t4g.micro, Single-AZ(2a 한 대) : 캡스톤 예산에 맞춘 최소 구성
# - private 서브넷에만 두고, rds-sg가 ECS 태스크(ecs-sg)의 3306만 허용한다 → 인터넷·내 PC에서는 직접 접속 불가
# - 작업하지 않을 때는 scripts/stop.sh로 중지한다 (중지된 RDS는 7일 뒤 AWS가 자동으로 다시 켠다)
#
# [DB 비밀번호]
# - Terraform이 무작위 비밀번호를 만들어 RDS와 SSM(/pharmlink/prod/DB_PASSWORD)에 같은 값을 한 번만 넣는다.
# - ephemeral(임시) 값 + *_wo(쓰기 전용) 속성이라 비밀번호가 코드에도 state(S3)에도 저장되지 않는다. (ssm.tf와 같은 방식)
# - 사람은 비밀번호를 알 필요가 없고, ECS 태스크가 SSM에서 꺼내 SPRING_DATASOURCE_PASSWORD로 쓴다. (ecs.tf에서 연결)
# - 비밀번호를 바꾸고 싶으면 아래 두 version 숫자를 함께 1 올린 뒤 apply한다. (둘 중 하나만 올리면 값이 서로 달라진다)

locals {
  db_username         = "pharmlink" # 마스터 사용자 이름 
  db_password_version = 1           # 비밀번호를 새로 만들어 넣고 싶을 때만 올린다

  # 백엔드 application.yaml의 기본 DB_URL과 같은 옵션, 호스트만 RDS 주소로 바꾼다 (ecs.tf, outputs.tf에서 사용)
  db_jdbc_url = "jdbc:mysql://${aws_db_instance.main.address}:${local.db_port}/${local.db_name}?serverTimezone=Asia/Seoul&characterEncoding=UTF-8"
}

# ---------- 1) 무작위 비밀번호 (apply 하는 동안에만 메모리에 있고 state에는 남지 않는다) ----------
ephemeral "random_password" "db" {
  length = 24
  # RDS MySQL 비밀번호에 쓸 수 없는 문자(/ @ " 공백)와 JDBC URL을 헷갈리게 하는 문자를 빼고 특수문자를 고른다
  override_special = "!#%^*-_=+"
}

# ---------- 2) DB 서브넷 그룹 : RDS를 둘 수 있는 서브넷 목록 ----------
# Single-AZ여도 AWS 규칙상 서로 다른 AZ 서브넷이 2개 이상 있어야 한다 (private-a, private-c)
resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = [for s in aws_subnet.private : s.id]

  tags = {
    Name = "${local.name_prefix}-db-subnet-group"
  }
}

# ---------- 3) 파라미터 그룹 : MySQL 서버 설정값 ----------
# 백엔드 결정 사항 : DB 시간은 KST로 저장 (application.yaml의 serverTimezone·hibernate time_zone과 맞춘다)
resource "aws_db_parameter_group" "mysql" {
  name   = "${local.name_prefix}-mysql84"
  family = "mysql8.4"

  parameter {
    name  = "time_zone"
    value = "Asia/Seoul"
  }

  # Flyway V1 테이블과 같은 문자셋·정렬 규칙 (한글·이모지 저장)
  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  tags = {
    Name = "${local.name_prefix}-mysql84"
  }
}

# ---------- 4) DB 인스턴스 본체 ----------
resource "aws_db_instance" "main" {
  identifier = local.db_identifier # pharmlink-prod-db (start.sh, stop.sh가 이 이름을 쓴다)

  engine                     = "mysql"
  engine_version             = "8.4" # 8.4의 최신 마이너 버전으로 만든다
  auto_minor_version_upgrade = true
  instance_class             = "db.t4g.micro" # 2 vCPU(버스트), 1GB 메모리

  allocated_storage = 20 # GB, gp3 최소 크기
  storage_type      = "gp3"
  storage_encrypted = true # AWS 관리 키(aws/rds)로 암호화, 추가 요금 없음

  db_name  = local.db_name # pharm_erp : 처음 만들 때 이 이름의 빈 데이터베이스를 만든다 (테이블은 Flyway가 만든다)
  username = local.db_username
  port     = local.db_port

  password_wo         = ephemeral.random_password.db.result
  password_wo_version = local.db_password_version

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.mysql.name
  publicly_accessible    = false          # 퍼블릭 IP를 주지 않는다
  multi_az               = false          # Single-AZ
  availability_zone      = local.azs["a"] # 구성도와 같이 2a에 둔다

  backup_retention_period  = 1    # 자동 백업 1일 (DB 크기만큼은 백업 저장 무료)
  delete_automated_backups = true # DB를 지우면 자동 백업도 같이 지운다
  skip_final_snapshot      = true # 12/3 이후 destroy 때 최종 스냅샷을 만들지 않는다 (스냅샷 보관 요금 방지)
  deletion_protection      = false
  apply_immediately        = true # 설정 변경을 다음 점검 시간까지 미루지 않고 바로 적용

  performance_insights_enabled = false # 추가 기능은 끈다 (비용·단순화)
  monitoring_interval          = 0

  tags = {
    Name = local.db_identifier
  }
}

# ---------- 5) DB 비밀번호를 SSM에 저장 ----------
# RDS가 만들어진 뒤에 같은 비밀번호를 넣는다 (RDS 생성이 실패하면 SSM도 만들지 않도록 순서를 건다)
resource "aws_ssm_parameter" "db_password" {
  name             = "${local.ssm_prefix}/DB_PASSWORD"
  type             = "SecureString"
  value_wo         = ephemeral.random_password.db.result
  value_wo_version = local.db_password_version

  depends_on = [aws_db_instance.main]
}
