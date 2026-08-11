variable "cluster_name" {
  type = string
}

variable "ebs_role_arn" {
  type = string
}

variable "ebs_addon_version" {
  type     = string
  default  = null
  nullable = true
}

variable "vpc_cni_role_arn" {
  type = string
}

variable "vpc_cni_addon_version" {
  type = string
}

variable "tags" {
  type = map(string)
}
