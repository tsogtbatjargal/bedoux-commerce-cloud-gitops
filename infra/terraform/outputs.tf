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

output "database_secret_name" {
  description = "Temporary P7.3 database secret name; null while secrets_manager_enabled is false."
  value       = try(module.database_secrets[0].secret_name, null)
}

output "database_secrets_api_role_arn" {
  description = "Temporary P7.3 API IRSA role ARN; null while secrets_manager_enabled is false."
  value       = try(module.database_secrets[0].role_arn, null)
}

output "cloudwatch_application_log_group_name" {
  description = "Temporary P8 application log group; null while observability_enabled is false."
  value       = try(module.observability[0].application_log_group_name, null)
}

output "route53_hosted_zone_id" {
  description = "P12 public hosted zone ID; null while route53_acm_enabled is false."
  value       = try(module.route53_acm[0].hosted_zone_id, null)
}

output "route53_name_servers" {
  description = "P12 apex-zone nameservers to configure at the registrar; empty while route53_acm_enabled is false."
  value       = try(module.route53_acm[0].hosted_zone_name_servers, [])
}

output "acm_certificate_arn" {
  description = "P12 validated ACM certificate ARN for the ALB; null while route53_acm_enabled is false."
  value       = try(module.route53_acm[0].certificate_arn, null)
}

output "route53_website_alias_fqdns" {
  description = "P12 apex/www alias FQDNs; empty while route53_aliases_enabled is false."
  value       = try(module.route53_acm[0].website_alias_fqdns, [])
}
