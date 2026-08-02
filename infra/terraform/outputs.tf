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

output "github_actions_role_arn" {
  description = "GitHub Actions OIDC deployment role ARN; create it only in a P6.4 AWS session."
  value       = module.github_actions_oidc.role_arn
}

output "rds_address" {
  description = "Private RDS hostname for a P7 session; null while rds_enabled is false."
  value       = try(module.rds[0].address, null)
}

output "rds_port" {
  description = "RDS PostgreSQL port for a P7 session; null while rds_enabled is false."
  value       = try(module.rds[0].port, null)
}

output "product_images_bucket_name" {
  description = "Temporary P7.2 bucket name; null while s3_images_enabled is false. Do not commit or retain a presigned URL."
  value       = try(module.product_images[0].bucket_name, null)
}

output "product_images_api_role_arn" {
  description = "Temporary P7.2 API IRSA role ARN; null while s3_images_enabled is false."
  value       = try(module.product_images[0].api_role_arn, null)
}
