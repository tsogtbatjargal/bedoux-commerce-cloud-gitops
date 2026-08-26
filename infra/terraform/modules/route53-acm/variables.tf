variable "domain_name" {
  description = "Domain for the public hosted zone and ACM certificate. Supply it without a trailing dot."
  type        = string

  validation {
    condition = (
      var.domain_name == lower(var.domain_name) &&
      strcontains(var.domain_name, ".") &&
      !startswith(var.domain_name, ".") &&
      !endswith(var.domain_name, ".") &&
      can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.domain_name))
    )
    error_message = "domain_name must be a lowercase DNS name without a leading or trailing dot."
  }
}

variable "subject_alternative_names" {
  description = "Additional certificate names inside the same hosted zone, such as www.example.com."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for name in var.subject_alternative_names :
      name == lower(name) && endswith(name, ".${var.domain_name}")
    ])
    error_message = "Every subject alternative name must be lowercase and below domain_name."
  }
}

variable "certificate_enabled" {
  description = "Create and DNS-validate the ACM certificate after parent-DNS delegation to the hosted zone is verified."
  type        = bool
  default     = false
}

variable "website_aliases_enabled" {
  description = "Create apex and subject-alternative-name aliases to the temporary P12 ALB."
  type        = bool
  default     = false
}

variable "website_alias_dns_name" {
  description = "DNS name of the controller-created P12 Application Load Balancer."
  type        = string
  default     = ""

  validation {
    condition = (
      var.website_alias_dns_name == "" ||
      endswith(var.website_alias_dns_name, ".elb.amazonaws.com")
    )
    error_message = "website_alias_dns_name must be empty or an AWS ELB DNS name."
  }
}

variable "website_alias_zone_id" {
  description = "Canonical hosted zone ID reported for the controller-created P12 ALB."
  type        = string
  default     = ""

  validation {
    condition = (
      var.website_alias_zone_id == "" ||
      can(regex("^Z[A-Z0-9]+$", var.website_alias_zone_id))
    )
    error_message = "website_alias_zone_id must be empty or an AWS canonical hosted zone ID."
  }
}

variable "validation_record_ttl" {
  description = "TTL in seconds for ACM DNS validation records."
  type        = number
  default     = 60

  validation {
    condition     = var.validation_record_ttl >= 60 && var.validation_record_ttl <= 300
    error_message = "validation_record_ttl must stay between 60 and 300 seconds for the bounded P12 validation session."
  }
}

variable "tags" {
  description = "Standard project tags applied to taggable DNS and certificate resources."
  type        = map(string)
}
