output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.this.arn
}

output "ebs_csi_role_arn" {
  value = aws_iam_role.ebs_csi.arn
}

output "alb_controller_role_arn" {
  value = aws_iam_role.alb_controller.arn
}

output "alb_controller_policy_arn" {
  value = aws_iam_policy.alb_controller.arn
}

