module "vpc" {
  source = "./modules/vpc"

  name                = var.cluster_name
  cidr                = var.vpc_cidr
  availability_zones  = var.availability_zones
  public_subnet_cidrs = var.public_subnet_cidrs
  tags                = local.tags
}

module "iam_cluster" {
  source = "./modules/iam-cluster"

  cluster_role_name        = "bedoux-eks-cluster-role"
  node_role_name           = "bedoux-eks-nodegroup-role"
  permissions_boundary_arn = local.project_role_permissions_boundary_arn
  tags                     = local.tags
}

module "eks" {
  source = "./modules/eks"

  cluster_name            = var.cluster_name
  kubernetes_version      = var.kubernetes_version
  subnet_ids              = module.vpc.public_subnet_ids
  cluster_role_arn        = module.iam_cluster.cluster_role_arn
  node_role_arn           = module.iam_cluster.node_role_arn
  github_actions_role_arn = module.github_actions_oidc.role_arn
  instance_types          = var.node_instance_types
  capacity_type           = var.node_capacity_type
  node_groups_per_az      = var.node_groups_per_az
  desired_size            = var.node_desired_size
  min_size                = var.node_min_size
  max_size                = var.node_max_size
  disk_size_gib           = var.node_disk_size_gib
  tags                    = local.tags
}

# Disabled by default so P6-only learning sessions continue to create exactly
# the previously reviewed EKS profile. P7.1 enables this explicitly for a
# bounded RDS exercise with TF_VAR_rds_master_password supplied out of band.
module "rds" {
  count  = var.rds_enabled ? 1 : 0
  source = "./modules/rds"

  name                          = var.cluster_name
  vpc_id                        = module.vpc.vpc_id
  subnet_ids                    = module.vpc.public_subnet_ids
  availability_zone             = var.availability_zones[0]
  eks_cluster_security_group_id = module.eks.cluster_security_group_id
  database_name                 = var.rds_database_name
  master_username               = var.rds_master_username
  master_password               = var.rds_master_password
  instance_class                = var.rds_instance_class
  allocated_storage_gib         = var.rds_allocated_storage_gib
  tags                          = local.tags
}

# P7.2 only: a short-lived private bucket and an IRSA role restricted to its
# synthetic product-image prefix. This module is intentionally *not* part of
# the persistent allowlist; the teardown helper destroys it with the session.
module "product_images" {
  count  = var.s3_images_enabled ? 1 : 0
  source = "./modules/s3-images"

  bucket_prefix            = "${var.cluster_name}-product-images-"
  image_source_directory   = "${path.root}/../../apps/web/public/static/products"
  oidc_provider_arn        = module.workload_iam.oidc_provider_arn
  oidc_issuer_url          = module.eks.oidc_issuer_url
  permissions_boundary_arn = local.project_role_permissions_boundary_arn
  tags                     = local.tags
}

# P7.3 only: create the temporary database secret and a separate API IRSA role.
# The secret value is held in encrypted Terraform state and AWS Secrets Manager;
# it is never rendered into a Kubernetes Secret or committed configuration.
module "database_secrets" {
  count  = var.secrets_manager_enabled && var.rds_enabled ? 1 : 0
  source = "./modules/secrets-manager"

  secret_name = var.secrets_manager_secret_name
  secret_string = jsonencode({
    DATABASE_URL = "postgresql+psycopg://${urlencode(var.rds_master_username)}:${urlencode(var.rds_master_password)}@${try(module.rds[0].address, "")}:${try(module.rds[0].port, 5432)}/${urlencode(var.rds_database_name)}"
  })
  role_name                 = "bedoux-secrets-manager-role"
  policy_name               = "bedoux-secrets-manager-policy"
  oidc_provider_arn         = module.workload_iam.oidc_provider_arn
  oidc_issuer_url           = module.eks.oidc_issuer_url
  service_account_namespace = "bedoux"
  service_account_name      = "bedoux-api-secrets"
  permissions_boundary_arn  = local.project_role_permissions_boundary_arn
  tags                      = local.tags
}

module "workload_iam" {
  source = "./modules/iam-workload"

  cluster_name             = var.cluster_name
  oidc_issuer_url          = module.eks.oidc_issuer_url
  permissions_boundary_arn = local.project_role_permissions_boundary_arn
  tags                     = local.tags
}

module "addons" {
  source = "./modules/eks-addons"

  cluster_name          = module.eks.cluster_name
  ebs_role_arn          = module.workload_iam.ebs_csi_role_arn
  ebs_addon_version     = var.ebs_csi_addon_version
  vpc_cni_role_arn      = module.workload_iam.vpc_cni_role_arn
  vpc_cni_addon_version = var.vpc_cni_addon_version
  tags                  = local.tags
}

# P8.2 only: CloudWatch Container Insights, structured application-log metrics,
# dashboard, and no-action alarms. Everything in this module is session-temporary;
# keep it disabled outside a reviewed P8 exercise.
module "observability" {
  count  = var.observability_enabled ? 1 : 0
  source = "./modules/observability"

  cluster_name             = module.eks.cluster_name
  oidc_provider_arn        = module.workload_iam.oidc_provider_arn
  oidc_issuer_url          = module.eks.oidc_issuer_url
  cloudwatch_addon_version = var.cloudwatch_observability_addon_version
  log_retention_days       = var.cloudwatch_log_retention_days
  alarms_enabled           = var.observability_alarms_enabled
  alb_arn_suffix           = var.observability_alb_arn_suffix
  rds_instance_identifier  = try(module.rds[0].identifier, "")
  permissions_boundary_arn = local.project_role_permissions_boundary_arn
  tags                     = local.tags
}

# P12.1 only: opt in after ADR 0022's apex-cutover and live-session gates are
# satisfied. The module deliberately manages DNS hosting and certificate
# validation, not domain registration or renewal.
module "route53_acm" {
  count  = var.route53_acm_enabled ? 1 : 0
  source = "./modules/route53-acm"

  certificate_enabled       = var.route53_acm_certificate_enabled
  domain_name               = var.route53_acm_domain_name
  subject_alternative_names = var.route53_acm_subject_alternative_names
  tags                      = local.tags
}

module "ecr" {
  source = "./modules/ecr"

  repository_names = ["bedoux-api", "bedoux-web"]
  tags             = local.tags
}

module "github_actions_oidc" {
  source = "./modules/github-actions-oidc"

  aws_region               = var.aws_region
  cluster_name             = var.cluster_name
  ecr_repository_arns      = module.ecr.repository_arns
  github_oidc_subject      = var.github_oidc_subject
  permissions_boundary_arn = local.project_role_permissions_boundary_arn
  tags                     = local.tags
}

check "no_nat_gateway" {
  assert {
    condition     = length(module.vpc.nat_gateway_ids) == 0
    error_message = "The learning VPC must not contain a NAT Gateway."
  }
}

check "rds_password_when_enabled" {
  assert {
    condition     = !var.rds_enabled || (var.rds_master_password != null && length(var.rds_master_password) >= 8)
    error_message = "Set a non-committed rds_master_password of at least eight characters when rds_enabled is true."
  }
}

check "observability_addon_version_when_enabled" {
  assert {
    condition     = !var.observability_enabled || var.cloudwatch_observability_addon_version != null
    error_message = "Set the exact reviewed cloudwatch_observability_addon_version when observability_enabled is true."
  }
}

check "observability_alarms_require_wiring" {
  assert {
    condition     = !var.observability_alarms_enabled || (var.observability_enabled && var.rds_enabled && var.observability_alb_arn_suffix != "")
    error_message = "P8 alarms require observability_enabled, rds_enabled, and a discovered observability_alb_arn_suffix."
  }
}

check "route53_acm_certificate_requires_zone" {
  assert {
    condition     = !var.route53_acm_certificate_enabled || var.route53_acm_enabled
    error_message = "Enable the Route 53 hosted zone before enabling its ACM certificate."
  }
}
