variable "bucket_prefix" {
  description = "Globally unique prefix for the temporary product-image bucket."
  type        = string
}

variable "image_source_directory" {
  description = "Directory containing the version-controlled synthetic SVG assets to stage."
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN used by the API ServiceAccount IRSA trust policy."
  type        = string
}

variable "oidc_issuer_url" {
  description = "EKS OIDC issuer URL used by the API ServiceAccount IRSA trust policy."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace containing the API ServiceAccount."
  type        = string
  default     = "bedoux"
}

variable "service_account_name" {
  description = "Only Kubernetes ServiceAccount allowed to assume the product-image role."
  type        = string
  default     = "bedoux-api"
}

variable "tags" {
  type = map(string)
}
