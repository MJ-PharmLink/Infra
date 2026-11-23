# [모니터링 : 문제가 생기면 메일로 알려준다]
#
# 흐름 : 지표(Metric) → 알람(Alarm)이 기준을 넘으면 → SNS 주제(Topic) → 구독한 메일로 발송
#   - 지표 : ALB·ECS·RDS가 1분/5분마다 CloudWatch에 자동으로 보내는 숫자 (따로 설치할 것 없음)
#   - 알람 : "이 숫자가 N분 동안 기준을 넘으면 울려라" 라는 규칙
#   - SNS  : 알람이 울리면 메시지를 받아서 구독자(메일)에게 뿌려주는 우체국
#
# stop.sh 로 꺼 두면 ECS·RDS 지표가 아예 안 들어온다 → treat_missing_data = "notBreaching"
# (데이터가 없으면 "정상"으로 본다) 로 해서, 일부러 꺼 둔 동안 알람이 울리지 않게 한다.
# 같은 이유로 "실행 중인 task가 0개" 알람은 만들지 않는다 (stop.sh 할 때마다 울리기 때문).

# ---------- 1) SNS 주제 + 메일 구독 ----------
resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts"
}

# 메일 주소마다 구독 1개. apply 후 AWS가 보낸 "Subscription Confirmation" 메일에서
# Confirm subscription 을 눌러야 메일이 오기 시작한다 (안 누르면 3일 뒤 자동 삭제)
resource "aws_sns_topic_subscription" "alert_email" {
  for_each = toset(var.alert_emails)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# ---------- 2) 알람 목록 ----------
# 알람마다 바뀌는 값만 표로 적고, 아래 resource 하나가 for_each 로 전부 만든다
#   period             : 몇 초 단위로 숫자를 모을지 (60 = 1분, 300 = 5분)
#   evaluation_periods : 그 단위가 몇 번 연속으로 기준을 넘어야 울릴지
#   statistic          : 모은 숫자를 합칠 방법 (Sum 합계, Average 평균, Maximum 최댓값, Minimum 최솟값)
locals {
  alarms = {
    # --- ALB : 사용자가 실제로 받는 응답 ---
    alb-target-5xx = {
      description        = "백엔드가 5분 동안 5xx 에러를 5번 이상 응답함 (서버 코드·DB 오류)"
      namespace          = "AWS/ApplicationELB"
      metric_name        = "HTTPCode_Target_5XX_Count"
      statistic          = "Sum"
      period             = 300
      evaluation_periods = 1
      comparison         = "GreaterThanOrEqualToThreshold"
      threshold          = 5
      dimensions         = { LoadBalancer = aws_lb.main.arn_suffix }
    }
    alb-elb-5xx = {
      description        = "ALB가 직접 5xx(502·503·504)를 10번 이상 응답함 (살아 있는 task가 없음). stop.sh 로 꺼 둔 상태에서 사이트에 접속해도 울린다"
      namespace          = "AWS/ApplicationELB"
      metric_name        = "HTTPCode_ELB_5XX_Count"
      statistic          = "Sum"
      period             = 300
      evaluation_periods = 1
      comparison         = "GreaterThanOrEqualToThreshold"
      threshold          = 10
      dimensions         = { LoadBalancer = aws_lb.main.arn_suffix }
    }
    alb-unhealthy-target = {
      description        = "헬스체크(/actuator/health)에 실패한 task가 3분 넘게 있음"
      namespace          = "AWS/ApplicationELB"
      metric_name        = "UnHealthyHostCount"
      statistic          = "Maximum"
      period             = 60
      evaluation_periods = 3
      comparison         = "GreaterThanOrEqualToThreshold"
      threshold          = 1
      dimensions = {
        LoadBalancer = aws_lb.main.arn_suffix
        TargetGroup  = aws_lb_target_group.backend.arn_suffix
      }
    }

    # --- ECS : 백엔드 컨테이너 (0.5 vCPU / 1GB) ---
    ecs-cpu-high = {
      description        = "백엔드 CPU 평균이 15분 동안 80% 이상"
      namespace          = "AWS/ECS"
      metric_name        = "CPUUtilization"
      statistic          = "Average"
      period             = 300
      evaluation_periods = 3
      comparison         = "GreaterThanOrEqualToThreshold"
      threshold          = 80
      dimensions = {
        ClusterName = aws_ecs_cluster.main.name
        ServiceName = aws_ecs_service.backend.name
      }
    }
    ecs-memory-high = {
      description        = "백엔드 메모리 평균이 15분 동안 85% 이상 (넘치면 컨테이너가 강제 종료됨)"
      namespace          = "AWS/ECS"
      metric_name        = "MemoryUtilization"
      statistic          = "Average"
      period             = 300
      evaluation_periods = 3
      comparison         = "GreaterThanOrEqualToThreshold"
      threshold          = 85
      dimensions = {
        ClusterName = aws_ecs_cluster.main.name
        ServiceName = aws_ecs_service.backend.name
      }
    }

    # --- RDS : MySQL (db.t4g.micro, 20GB) ---
    rds-cpu-high = {
      description        = "DB CPU 평균이 15분 동안 80% 이상"
      namespace          = "AWS/RDS"
      metric_name        = "CPUUtilization"
      statistic          = "Average"
      period             = 300
      evaluation_periods = 3
      comparison         = "GreaterThanOrEqualToThreshold"
      threshold          = 80
      dimensions         = { DBInstanceIdentifier = aws_db_instance.main.identifier }
    }
    rds-storage-low = {
      description        = "DB 남은 저장공간이 2GB 미만"
      namespace          = "AWS/RDS"
      metric_name        = "FreeStorageSpace"
      statistic          = "Minimum"
      period             = 300
      evaluation_periods = 1
      comparison         = "LessThanThreshold"
      threshold          = 2 * 1024 * 1024 * 1024 # 바이트 단위
      dimensions         = { DBInstanceIdentifier = aws_db_instance.main.identifier }
    }
    rds-memory-low = {
      description        = "DB 여유 메모리가 15분 동안 100MB 미만"
      namespace          = "AWS/RDS"
      metric_name        = "FreeableMemory"
      statistic          = "Average"
      period             = 300
      evaluation_periods = 3
      comparison         = "LessThanThreshold"
      threshold          = 100 * 1024 * 1024 # 바이트 단위
      dimensions         = { DBInstanceIdentifier = aws_db_instance.main.identifier }
    }
  }
}

# ---------- 3) 알람 만들기 (위 표 8개를 하나씩) ----------
resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.alarms

  alarm_name          = "${local.name_prefix}-${each.key}" # 예) pharmlink-prod-rds-cpu-high
  alarm_description   = each.value.description
  namespace           = each.value.namespace
  metric_name         = each.value.metric_name
  statistic           = each.value.statistic
  period              = each.value.period
  evaluation_periods  = each.value.evaluation_periods
  comparison_operator = each.value.comparison
  threshold           = each.value.threshold
  dimensions          = each.value.dimensions
  treat_missing_data  = "notBreaching" # 꺼 둔 동안(데이터 없음)은 정상으로 본다

  alarm_actions = [aws_sns_topic.alerts.arn] # 울릴 때 메일
  ok_actions    = [aws_sns_topic.alerts.arn] # 정상으로 돌아올 때도 메일
}
