resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = var.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = var.ebs_addon_version
  service_account_role_arn = var.ebs_role_arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name             = var.cluster_name
  addon_name               = "vpc-cni"
  addon_version            = var.vpc_cni_addon_version
  service_account_role_arn = var.vpc_cni_role_arn
  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
  })

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags
}
