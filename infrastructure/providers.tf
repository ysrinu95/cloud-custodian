terraform {
  required_version = "~> 1.12"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.45"
    }
  }

  backend "s3" {
    region       = "us-west-2"
    bucket       = "gs-s3-shared-usw2-terraform-state"
    key          = "devops/cloud-custodian/infrastructure/terraform.tfstate"
    use_lockfile = true
    profile      = "backend"
  }
}

provider "aws" {
  region = "us-west-2"

  # profile = local
  # assume_role_with_web_identity = pipeline
  profile = var.profile
  dynamic "assume_role_with_web_identity" {
    for_each = var.profile == null ? ["true"] : []
    content {
      role_arn                = local.workspace.role
      web_identity_token_file = "/tmp/web-identity-token"
    }
  }

  default_tags {
    tags = {
      contact     = "devops@greenstreet.com"
      deployed-by = "automation:terraform"
      environment = local.workspace.environment
      repo        = "devops/cloud-custodian/infrastructure"
      squad       = "devops"
      owner       = "devops"
    }
  }

  ignore_tags {
    key_prefixes = [
      "c7n:"
    ]
  }
}
