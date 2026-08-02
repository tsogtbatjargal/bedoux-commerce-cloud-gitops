provider "aws" {
  region  = var.aws_region
  profile = var.skip_aws_credentials_validation ? null : var.aws_profile
  # Terraform validate still initializes the provider. Supply inert values in
  # explicitly offline mode so the AWS SDK does not fall back to the host
  # profile or credential chain and make a network call during local/CI checks.
  access_key                  = var.skip_aws_credentials_validation ? "offline-validation-access-key" : null
  secret_key                  = var.skip_aws_credentials_validation ? "offline-validation-secret-key" : null
  skip_credentials_validation = var.skip_aws_credentials_validation
  skip_metadata_api_check     = var.skip_aws_credentials_validation
  skip_requesting_account_id  = var.skip_aws_credentials_validation

  default_tags {
    tags = local.tags
  }
}

provider "tls" {}
