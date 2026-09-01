variable "aws_region" {
  description = "Pinned AWS region for the learning environment."
  type        = string
  default     = "ca-central-1"

  validation {
    condition     = var.aws_region == "ca-central-1"
    error_message = "The learning environment is pinned to ca-central-1."
  }
}

variable "aws_profile" {
  description = "Named non-root AWS CLI profile used for this project."
  type        = string
  default     = "bedoux-admin"
}

variable "skip_aws_credentials_validation" {
  description = "Only for offline Terraform validation; never use for an AWS plan or apply."
  type        = bool
  default     = false
}

variable "github_oidc_subject" {
  description = "Exact GitHub OIDC subject allowed to obtain the deployment role; this organization uses GitHub's custom numeric-ID subject template and is restricted to main."
  type        = string
  default     = "repo:bedoux-tech@290496053/bedoux-commerce-cloud@1304975065:ref:refs/heads/main"
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
  default     = "bedoux"
}

variable "kubernetes_version" {
  description = "Pinned EKS Kubernetes minor version."
  type        = string
  default     = "1.34"

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "kubernetes_version must be a Kubernetes minor version such as 1.34."
  }
}

variable "availability_zones" {
  description = "Two public-subnet AZs for the EKS control plane and managed node groups."
  type        = list(string)
  default     = ["ca-central-1a", "ca-central-1b"]

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "The learning profile requires exactly two availability zones."
  }
}

variable "vpc_cidr" {
  description = "Learning VPC CIDR."
  type        = string
  default     = "10.42.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "One public subnet CIDR per availability zone."
  type        = list(string)
  default     = ["10.42.0.0/20", "10.42.16.0/20"]

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "Exactly two public subnet CIDRs are required."
  }
}

variable "node_instance_types" {
  description = "Managed node group instance types; Spot profiles should use same-shape alternatives."
  type        = list(string)
  default     = ["t3.medium", "t3a.medium"]
}

variable "node_capacity_type" {
  description = "Managed node group purchase model."
  type        = string
  default     = "SPOT"

  validation {
    condition     = contains(["SPOT", "ON_DEMAND"], var.node_capacity_type)
    error_message = "node_capacity_type must be SPOT or ON_DEMAND."
  }
}

variable "node_groups_per_az" {
  description = "Opt in to two one-node managed node groups, each pinned to one configured AZ; reserved for the bounded P11 HA profile."
  type        = bool
  default     = false
}

variable "node_desired_size" {
  description = "Managed node group desired size."
  type        = number
  default     = 1
}

variable "node_min_size" {
  description = "Managed node group minimum size."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Managed node group maximum size."
  type        = number
  default     = 1
}

variable "node_disk_size_gib" {
  description = "Managed node root volume size."
  type        = number
  default     = 20
}

variable "ebs_csi_addon_version" {
  description = "Exact EBS CSI add-on version compatible with kubernetes_version."
  type        = string
  default     = "v1.63.1-eksbuild.1"
}

variable "vpc_cni_addon_version" {
  description = "Exact VPC CNI add-on version compatible with kubernetes_version."
  type        = string
  default     = "v1.22.4-eksbuild.3"
}

variable "rds_enabled" {
  description = "Create the short-lived P7 Single-AZ RDS instance. Keep false outside a reviewed P7 session."
  type        = bool
  default     = false
}

variable "rds_database_name" {
  description = "Initial database name for the P7 RDS instance."
  type        = string
  default     = "bedoux"
}

variable "rds_master_username" {
  description = "RDS master username for the P7 learning session."
  type        = string
  default     = "bedoux"
}

variable "rds_master_password" {
  description = "Sensitive RDS master password supplied only out of band for an enabled P7 session; P7.3 replaces this bootstrap path with Secrets Manager."
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
}

variable "rds_instance_class" {
  description = "Smallest reviewed RDS instance class for the short-lived P7 learning exercise."
  type        = string
  default     = "db.t4g.micro"
}

variable "rds_allocated_storage_gib" {
  description = "Fixed gp3 storage allocation for the P7 RDS instance; autoscaling is intentionally omitted."
  type        = number
  default     = 20
}

variable "secrets_manager_enabled" {
  description = "Create the short-lived P7.3 database secret and API IRSA role; requires rds_enabled=true."
  type        = bool
  default     = false
}

variable "secrets_manager_secret_name" {
  description = "Stable, non-secret name for the short-lived P7.3 database credential."
  type        = string
  default     = "bedoux-rds-credentials"

  validation {
    condition     = can(regex("^bedoux-[a-z0-9-]+$", var.secrets_manager_secret_name))
    error_message = "The Secrets Manager name must begin with bedoux- and contain only lowercase letters, digits, and hyphens."
  }
}

variable "s3_images_enabled" {
  description = "Create the short-lived P7.2 private product-image bucket and API IRSA role. Keep false outside a reviewed P7.2 session."
  type        = bool
  default     = false
}

variable "observability_enabled" {
  description = "Create the temporary P8.2 CloudWatch observability resources. Keep false outside a reviewed P8 session."
  type        = bool
  default     = false
}

variable "cloudwatch_observability_addon_version" {
  description = "Exact amazon-cloudwatch-observability EKS add-on version reviewed for the active P8 session."
  type        = string
  default     = null
  nullable    = true
}

variable "cloudwatch_log_retention_days" {
  description = "P8 CloudWatch Container Insights log retention; fixed to the learning-profile three-day limit."
  type        = number
  default     = 3

  validation {
    condition     = var.cloudwatch_log_retention_days == 3
    error_message = "CloudWatch log retention must remain three days in the learning profile."
  }
}

variable "observability_alarms_enabled" {
  description = "Create P8 dashboard alarms after the ALB is available. All alarms are notification-free learning evidence."
  type        = bool
  default     = false
}

variable "observability_alb_arn_suffix" {
  description = "Non-sensitive ALB ARN suffix (app/name/id) discovered after the session Ingress is created; never commit a full ARN."
  type        = string
  default     = ""

  validation {
    condition     = var.observability_alb_arn_suffix == "" || can(regex("^app/[A-Za-z0-9-]+/[0-9a-f]+$", var.observability_alb_arn_suffix))
    error_message = "observability_alb_arn_suffix must be empty or an ALB ARN suffix in app/name/id form."
  }
}

variable "route53_acm_enabled" {
  description = "Create the P12 Route 53 public hosted zone and DNS-validated ACM certificate. Keep false outside an approved P12 session."
  type        = bool
  default     = false
}

variable "route53_acm_domain_name" {
  description = "Owner-selected P12 apex domain recorded by ADR 0022."
  type        = string
  default     = "bedoux.ca"

  validation {
    condition     = var.route53_acm_domain_name == "bedoux.ca"
    error_message = "ADR 0022 fixes the P12 learning domain to bedoux.ca."
  }
}

variable "route53_acm_certificate_enabled" {
  description = "Create and validate the P12 ACM certificate after bedoux.ca delegates to its managed Route 53 zone."
  type        = bool
  default     = false
}

variable "route53_acm_subject_alternative_names" {
  description = "Additional P12 website aliases covered by the ACM certificate; ADR 0022 requires www.bedoux.ca."
  type        = list(string)
  default     = ["www.bedoux.ca"]

  validation {
    condition = (
      length(var.route53_acm_subject_alternative_names) == 1 &&
      contains(var.route53_acm_subject_alternative_names, "www.bedoux.ca")
    )
    error_message = "ADR 0022 requires exactly one additional certificate name: www.bedoux.ca."
  }
}

variable "route53_aliases_enabled" {
  description = "Create P12 apex/www aliases only after the temporary ALB target is discovered and reviewed."
  type        = bool
  default     = false
}

variable "route53_alias_target_dns_name" {
  description = "Temporary P12 ALB DNS name discovered after its Ingress is ready; never commit a live value."
  type        = string
  default     = ""

  validation {
    condition = (
      var.route53_alias_target_dns_name == "" ||
      endswith(var.route53_alias_target_dns_name, ".elb.amazonaws.com")
    )
    error_message = "route53_alias_target_dns_name must be empty or an AWS ELB DNS name."
  }
}

variable "route53_alias_target_zone_id" {
  description = "Temporary P12 ALB canonical hosted zone ID discovered with ELBv2."
  type        = string
  default     = ""

  validation {
    condition = (
      var.route53_alias_target_zone_id == "" ||
      can(regex("^Z[A-Z0-9]+$", var.route53_alias_target_zone_id))
    )
    error_message = "route53_alias_target_zone_id must be empty or an AWS canonical hosted zone ID."
  }
}

check "secrets_manager_requires_rds" {
  assert {
    condition     = !var.secrets_manager_enabled || var.rds_enabled
    error_message = "Enable rds_enabled before enabling the P7.3 database secret."
  }
}
