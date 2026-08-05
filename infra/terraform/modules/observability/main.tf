locals {
  oidc_issuer_host        = trimprefix(var.oidc_issuer_url, "https://")
  metrics_namespace       = "Bedoux/Application"
  alarms_enabled_with_alb = var.alarms_enabled && var.alb_arn_suffix != ""
  alarms_enabled_with_rds = var.alarms_enabled && var.rds_instance_identifier != ""
  # The EKS CloudWatch Observability add-on emits its own performance log group
  # in addition to application, dataplane, and host. Manage all four explicitly
  # so the learning profile never leaves telemetry at the AWS default retention.
  container_insights_log_kinds = toset(["application", "dataplane", "host", "performance"])
}

resource "aws_cloudwatch_log_group" "container_insights" {
  for_each = local.container_insights_log_kinds

  name              = "/aws/containerinsights/${var.cluster_name}/${each.value}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

data "aws_iam_policy_document" "agent_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:sub"
      values   = ["system:serviceaccount:amazon-cloudwatch:cloudwatch-agent"]
    }
  }
}

resource "aws_iam_role" "agent" {
  name               = "bedoux-cloudwatch-observability-role"
  assume_role_policy = data.aws_iam_policy_document.agent_assume_role.json
  tags               = var.tags
}

# AWS documents this managed policy as the supported permission set for the EKS
# CloudWatch Observability add-on. IRSA restricts its use to the add-on's one
# service account instead of granting telemetry access to every worker node.
resource "aws_iam_role_policy_attachment" "agent" {
  role       = aws_iam_role.agent.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name             = var.cluster_name
  addon_name               = "amazon-cloudwatch-observability"
  addon_version            = var.cloudwatch_addon_version
  service_account_role_arn = aws_iam_role.agent.arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags

  depends_on = [aws_cloudwatch_log_group.container_insights]
}

resource "aws_cloudwatch_log_metric_filter" "request_count" {
  name           = "bedoux-http-request-count"
  log_group_name = aws_cloudwatch_log_group.container_insights["application"].name
  pattern        = "{ $.event = \"http_request_completed\" }"

  metric_transformation {
    name          = "RequestCount"
    namespace     = local.metrics_namespace
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "server_error_count" {
  name           = "bedoux-http-server-error-count"
  log_group_name = aws_cloudwatch_log_group.container_insights["application"].name
  pattern        = "{ $.event = \"http_request_completed\" && $.status_code >= 500 }"

  metric_transformation {
    name          = "ServerErrorCount"
    namespace     = local.metrics_namespace
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_dashboard" "learning" {
  dashboard_name = "bedoux-learning-observability"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "Bedoux API request volume and 5xx rate"
          region  = "ca-central-1"
          view    = "timeSeries"
          stacked = false
          period  = 60
          metrics = [
            [{ expression = "IF(requests>0,100*errors/requests,0)", id = "error_rate", label = "5xx rate (%)" }],
            [local.metrics_namespace, "RequestCount", { id = "requests", stat = "Sum", label = "Requests" }],
            [".", "ServerErrorCount", { id = "errors", stat = "Sum", visible = false }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ALB unhealthy targets (dynamic session discovery)"
          region = "ca-central-1"
          view   = "timeSeries"
          period = 60
          metrics = [
            [{ expression = "SEARCH('{AWS/ApplicationELB,LoadBalancer} MetricName=\"UnHealthyHostCount\"', 'Maximum', 60)", id = "unhealthy" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Bedoux namespace pod restarts"
          region = "ca-central-1"
          view   = "timeSeries"
          period = 60
          metrics = [
            ["ContainerInsights", "pod_number_of_container_restarts", "ClusterName", var.cluster_name, "Namespace", "bedoux", { stat = "Maximum" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Short-lived RDS CPU utilization"
          region = "ca-central-1"
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.rds_instance_identifier, { stat = "Average", label = "RDS CPU (%)" }],
          ]
        }
      },
    ]
  })
}

resource "aws_cloudwatch_metric_alarm" "api_error_rate" {
  count = var.alarms_enabled ? 1 : 0

  alarm_name          = "bedoux-api-5xx-rate"
  alarm_description   = "P8 learning alarm: API structured-log 5xx rate is at least 1 percent. No automated action is configured."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  threshold           = 1
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "error_rate"
    expression  = "IF(requests>0,100*errors/requests,0)"
    label       = "API 5xx rate (%)"
    return_data = true
  }

  metric_query {
    id = "requests"
    metric {
      namespace   = local.metrics_namespace
      metric_name = "RequestCount"
      period      = 60
      stat        = "Sum"
    }
  }

  metric_query {
    id = "errors"
    metric {
      namespace   = local.metrics_namespace
      metric_name = "ServerErrorCount"
      period      = 60
      stat        = "Sum"
    }
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_targets" {
  count = local.alarms_enabled_with_alb ? 1 : 0

  alarm_name          = "bedoux-alb-unhealthy-targets"
  alarm_description   = "P8 learning alarm: the session ALB reports at least one unhealthy target. No automated action is configured."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  dimensions          = { LoadBalancer = var.alb_arn_suffix }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "pod_restarts" {
  count = var.alarms_enabled ? 1 : 0

  alarm_name          = "bedoux-pod-restarts"
  alarm_description   = "P8 learning alarm: a Bedoux namespace pod has restarted. No automated action is configured."
  namespace           = "ContainerInsights"
  metric_name         = "pod_number_of_container_restarts"
  dimensions          = { ClusterName = var.cluster_name, Namespace = "bedoux" }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu_utilization" {
  count = local.alarms_enabled_with_rds ? 1 : 0

  alarm_name          = "bedoux-rds-cpu-utilization"
  alarm_description   = "P8 learning alarm: the short-lived RDS instance CPU utilization is at least 80 percent. No automated action is configured."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = var.rds_instance_identifier }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  threshold           = 80
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  tags                = var.tags
}
