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

  cluster_role_name = "bedoux-eks-cluster-role"
  node_role_name    = "bedoux-eks-nodegroup-role"
  tags              = local.tags
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

  bucket_prefix          = "${var.cluster_name}-product-images-"
  image_source_directory = "${path.root}/../../apps/web/public/static/products"
  oidc_provider_arn      = module.workload_iam.oidc_provider_arn
  oidc_issuer_url        = module.eks.oidc_issuer_url
  tags                   = local.tags
}

module "workload_iam" {
  source = "./modules/iam-workload"

  cluster_name    = var.cluster_name
  oidc_issuer_url = module.eks.oidc_issuer_url
  tags            = local.tags
}

module "addons" {
  source = "./modules/eks-addons"

  cluster_name      = module.eks.cluster_name
  ebs_role_arn      = module.workload_iam.ebs_csi_role_arn
  ebs_addon_version = var.ebs_csi_addon_version
  tags              = local.tags
}

module "ecr" {
  source = "./modules/ecr"

  repository_names = ["bedoux-api", "bedoux-web"]
  tags             = local.tags
}

module "github_actions_oidc" {
  source = "./modules/github-actions-oidc"

  aws_region          = var.aws_region
  cluster_name        = var.cluster_name
  ecr_repository_arns = module.ecr.repository_arns
  github_oidc_subject = var.github_oidc_subject
  tags                = local.tags
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
