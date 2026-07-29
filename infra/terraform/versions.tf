terraform {
  required_version = "= 1.15.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.100.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "= 4.1.0"
    }
  }
}

