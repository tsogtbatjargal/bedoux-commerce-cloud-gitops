variable "cluster_name" {
  description = "EKS cluster whose temporary Container Insights data is collected."
  type        = string
}

variable "oidc_provider_arn" {
  description = "Cluster OIDC provider used to scope the CloudWatch agent IRSA role."
  type        = string
}

variable "oidc_issuer_url" {
  description = "Cluster OIDC issuer used in the CloudWatch agent IRSA trust policy."
  type        = string
}

variable "permissions_boundary_arn" {
  description = "Immutable maximum-permissions boundary required on every delegated project role."
  type        = string
}

variable "cloudwatch_addon_version" {
  description = "Exact EKS amazon-cloudwatch-observability add-on version reviewed for this session."
  type        = string
}

variable "log_retention_days" {
  description = "Short retention for every temporary Container Insights log group."
  type        = number
  default     = 3

  validation {
    condition     = var.log_retention_days == 3
    error_message = "The learning profile keeps CloudWatch logs for exactly three days."
  }
}

variable "alarms_enabled" {
  description = "Create the reviewed dashboard and no-action alarms after the ALB exists."
  type        = bool
  default     = false
}

variable "alb_arn_suffix" {
  description = "Non-sensitive Application Load Balancer ARN suffix (app/name/id), supplied only after the session Ingress creates it."
  type        = string
  default     = ""
}

variable "rds_instance_identifier" {
  description = "Optional short-lived RDS identifier to monitor during a P8 session."
  type        = string
  default     = ""
}

variable "tags" {
  type = map(string)
}
