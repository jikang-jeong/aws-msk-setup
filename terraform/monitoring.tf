# Amazon Managed Grafana for MSK Monitoring

# Grafana Workspace
resource "aws_grafana_workspace" "msk" {
  name                     = "${var.cluster_name}-grafana"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "SERVICE_MANAGED"
  role_arn                 = aws_iam_role.grafana.arn

  data_sources = ["PROMETHEUS", "CLOUDWATCH"]

  configuration = jsonencode({
    unifiedAlerting = {
      enabled = true
    }
  })
}

# IAM Role for Grafana
resource "aws_iam_role" "grafana" {
  name = "${var.cluster_name}-grafana-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "grafana.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "grafana_cloudwatch" {
  name = "${var.cluster_name}-grafana-cloudwatch"
  role = aws_iam_role.grafana.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarmsForMetric",
          "cloudwatch:DescribeAlarmHistory",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetInsightRuleReport"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:GetLogGroupFields",
          "logs:StartQuery",
          "logs:StopQuery",
          "logs:GetQueryResults",
          "logs:GetLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeTags",
          "ec2:DescribeInstances",
          "ec2:DescribeRegions"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["tag:GetResources"]
        Resource = "*"
      }
    ]
  })
}

# Amazon Managed Prometheus (AMP) for MSK metrics
resource "aws_prometheus_workspace" "msk" {
  alias = "${var.cluster_name}-prometheus"

  tags = var.tags
}

resource "aws_iam_role_policy" "grafana_prometheus" {
  name = "${var.cluster_name}-grafana-prometheus"
  role = aws_iam_role.grafana.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "aps:ListWorkspaces",
        "aps:DescribeWorkspace",
        "aps:QueryMetrics",
        "aps:GetLabels",
        "aps:GetSeries",
        "aps:GetMetricMetadata"
      ]
      Resource = "*"
    }]
  })
}

# Output
output "grafana_url" {
  value       = "https://${aws_grafana_workspace.msk.endpoint}"
  description = "Amazon Managed Grafana Workspace URL"
}

output "prometheus_endpoint" {
  value       = aws_prometheus_workspace.msk.prometheus_endpoint
  description = "Amazon Managed Prometheus Endpoint"
}
