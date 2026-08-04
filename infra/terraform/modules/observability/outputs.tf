output "application_log_group_name" {
  description = "Temporary application stdout log group collected by the EKS observability add-on."
  value       = aws_cloudwatch_log_group.container_insights["application"].name
}

output "agent_role_arn" {
  description = "Temporary IRSA role used only by the CloudWatch agent service account."
  value       = aws_iam_role.agent.arn
}
