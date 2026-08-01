output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "oidc_issuer_url" {
  value = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "cluster_security_group_id" {
  description = "EKS cluster security group used as the least-privilege RDS ingress source."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}
