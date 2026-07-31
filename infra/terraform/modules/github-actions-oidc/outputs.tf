output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.this.arn
}

output "role_arn" {
  value = aws_iam_role.this.arn
}

output "policy_arn" {
  value = aws_iam_policy.deployment.arn
}
