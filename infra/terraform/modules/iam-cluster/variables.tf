variable "cluster_role_name" {
  type = string
}

variable "node_role_name" {
  type = string
}

variable "permissions_boundary_arn" {
  description = "Immutable maximum-permissions boundary required on every delegated project role."
  type        = string
}

variable "tags" {
  type = map(string)
}
