###############################################################################
# CloudWatch Metric Filters & Alarms
# Triggers CloudWatch alarms based on patterns in application log groups
###############################################################################

locals {
  sns_topic_arn    = "arn:aws:sns:ap-south-1:${var.account_id}:prod-alerts"
  alarm_period     = 300
  eval_periods     = 1
}

# ── Log Metric Filters ────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_metric_filter" "application_errors" {
  name           = "prod-application-error-count"
  log_group_name = "/prod/application/error"
  pattern        = "[timestamp, level=ERROR, ...]"

  metric_transformation {
    name          = "ApplicationErrorCount"
    namespace     = "Prod/Application"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "payment_failures" {
  name           = "prod-payment-failure-count"
  log_group_name = "/prod/payment/transactions"
  pattern        = "[timestamp, level, message=\"*PAYMENT_FAILED*\", ...]"

  metric_transformation {
    name          = "PaymentFailureCount"
    namespace     = "Prod/Payment"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "payment_success" {
  name           = "prod-payment-success-count"
  log_group_name = "/prod/payment/transactions"
  pattern        = "[timestamp, level, message=\"*PAYMENT_SUCCESS*\", ...]"

  metric_transformation {
    name          = "PaymentSuccessCount"
    namespace     = "Prod/Payment"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "db_slow_query" {
  name           = "prod-db-slow-query"
  log_group_name = "/prod/application/app"
  pattern        = "[timestamp, level, message=\"*Slow query detected*\", ...]"

  metric_transformation {
    name          = "SlowQueryCount"
    namespace     = "Prod/Database"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "nginx_5xx" {
  name           = "prod-nginx-5xx-errors"
  log_group_name = "/prod/nginx/access"
  # Match lines where HTTP status starts with 5
  pattern        = "[ip, dash, user, timestamp, request, status_code=5*, bytes, ...]"

  metric_transformation {
    name          = "Nginx5xxCount"
    namespace     = "Prod/Nginx"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "oom_kill" {
  name           = "prod-oom-kill"
  log_group_name = "/prod/system/syslog"
  pattern        = "\"Out of memory\""

  metric_transformation {
    name          = "OOMKillCount"
    namespace     = "Prod/System"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

# ── CloudWatch Alarms ─────────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "high_application_errors" {
  alarm_name          = "prod-high-application-errors"
  alarm_description   = "Application error rate exceeds threshold in logs"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = local.eval_periods
  metric_name         = "ApplicationErrorCount"
  namespace           = "Prod/Application"
  period              = local.alarm_period
  statistic           = "Sum"
  threshold           = 50
  treat_missing_data  = "notBreaching"
  alarm_actions       = [local.sns_topic_arn]
  ok_actions          = [local.sns_topic_arn]

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "payment_failure_spike" {
  alarm_name          = "prod-payment-failure-spike"
  alarm_description   = "Payment failure count exceeds 10 in a 5-minute window"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = local.eval_periods
  metric_name         = "PaymentFailureCount"
  namespace           = "Prod/Payment"
  period              = local.alarm_period
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"
  alarm_actions       = [local.sns_topic_arn]
  ok_actions          = [local.sns_topic_arn]

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "nginx_5xx_alarm" {
  alarm_name          = "prod-nginx-5xx-high"
  alarm_description   = "High rate of 5xx responses from Nginx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = local.eval_periods
  metric_name         = "Nginx5xxCount"
  namespace           = "Prod/Nginx"
  period              = local.alarm_period
  statistic           = "Sum"
  threshold           = 100
  treat_missing_data  = "notBreaching"
  alarm_actions       = [local.sns_topic_arn]

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "oom_kill_alarm" {
  alarm_name          = "prod-oom-kill-detected"
  alarm_description   = "OOM kill detected on a production instance"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "OOMKillCount"
  namespace           = "Prod/System"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = [local.sns_topic_arn]

  tags = var.common_tags
}

# ── Variables ─────────────────────────────────────────────────────────────────

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "production"
    ManagedBy   = "terraform"
    Project     = "observability-stack"
  }
}
