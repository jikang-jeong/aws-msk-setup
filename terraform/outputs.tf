output "bootstrap_brokers_tls" {
  value = aws_msk_cluster.main.bootstrap_brokers_tls
}

output "zookeeper_connect_string" {
  value = aws_msk_cluster.main.zookeeper_connect_string
}

output "cluster_arn" {
  value = aws_msk_cluster.main.arn
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.main.api_endpoint
}

output "bastion_public_ip" {
  value       = aws_eip.bastion.public_ip
  description = "Bastion 고정 퍼블릭 IP (Elastic IP)"
}

output "dashboard_url" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${var.cluster_name}-dashboard"
}

output "msk_cluster_arn" {
  value       = aws_msk_cluster.main.arn
  description = "MSK Cluster ARN"
}

output "grafana_workspace_id" {
  value       = aws_grafana_workspace.msk.id
  description = "Grafana Workspace ID (Admin 권한 설정용)"
}
