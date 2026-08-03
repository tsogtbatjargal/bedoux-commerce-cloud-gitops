variable "secret_name" {
  type = string
}

variable "secret_string" {
  type      = string
  sensitive = true
}

variable "role_name" {
  type = string
}

variable "policy_name" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_issuer_url" {
  type = string
}

variable "service_account_namespace" {
  type = string
}

variable "service_account_name" {
  type = string
}

variable "tags" {
  type = map(string)
}
