variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "cluster_role_arn" {
  type = string
}

variable "node_role_arn" {
  type = string
}

variable "github_actions_role_arn" {
  type = string
}

variable "instance_types" {
  type = list(string)
}

variable "capacity_type" {
  type = string
}

variable "node_groups_per_az" {
  type = bool
}

variable "desired_size" {
  type = number
}

variable "min_size" {
  type = number
}

variable "max_size" {
  type = number
}

variable "disk_size_gib" {
  type = number
}

variable "tags" {
  type = map(string)

  validation {
    condition = alltrue([
      for key in ["project", "environment"] : try(length(trimspace(var.tags[key])) > 0, false)
    ])
    error_message = "tags must include non-empty project and environment values."
  }
}
