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

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  subnet_ids         = module.vpc.public_subnet_ids
  cluster_role_arn   = module.iam_cluster.cluster_role_arn
  node_role_arn      = module.iam_cluster.node_role_arn
  instance_types     = var.node_instance_types
  capacity_type      = var.node_capacity_type
  desired_size       = var.node_desired_size
  min_size           = var.node_min_size
  max_size           = var.node_max_size
  disk_size_gib      = var.node_disk_size_gib
  tags               = local.tags
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

check "no_nat_gateway" {
  assert {
    condition     = length(module.vpc.nat_gateway_ids) == 0
    error_message = "The learning VPC must not contain a NAT Gateway."
  }
}

