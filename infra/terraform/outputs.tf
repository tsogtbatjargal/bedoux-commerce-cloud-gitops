output "vpc_id" {
  description = "Learning VPC ID."
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs used by EKS."
  value       = module.vpc.public_subnet_ids
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_oidc_issuer_url" {
  description = "EKS OIDC issuer URL used by workload IAM roles."
  value       = module.eks.oidc_issuer_url
}

output "ecr_repository_urls" {
  description = "ECR repository URLs for the API and web images."
  value       = module.ecr.repository_urls
}

