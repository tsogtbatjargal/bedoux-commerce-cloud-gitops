provider "aws" {
  region                      = var.aws_region
  profile                     = var.skip_aws_credentials_validation ? null : var.aws_profile
  skip_credentials_validation = var.skip_aws_credentials_validation
  skip_metadata_api_check     = var.skip_aws_credentials_validation
  skip_requesting_account_id  = var.skip_aws_credentials_validation

  default_tags {
    tags = local.tags
  }
}

provider "tls" {}
