variable "aws_region" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "ecr_repository_arns" {
  type = list(string)
}

variable "github_repository" {
  type = string
}

variable "github_branch" {
  type = string
}

variable "oidc_issuer_url" {
  type    = string
  default = "https://token.actions.githubusercontent.com"
}

variable "tags" {
  type = map(string)
}
