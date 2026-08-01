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
  description = "Two public-subnet AZs for the EKS control plane and node group."
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
  description = "Managed node group instance types."
  type        = list(string)
  default     = ["t3.medium"]
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
  default     = "v1.63.0-eksbuild.1"
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
