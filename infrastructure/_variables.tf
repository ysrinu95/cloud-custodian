variable "profile" {
  default     = null
  description = "Local AWS profile to use when running locally."
}

variable "bitbucket_provider" {
  default     = "api.bitbucket.org/2.0/workspaces/greenstreetadvisors/pipelines-config/identity/oidc"
  description = "The Bitbucket OIDC provider."
}

locals {
  workspace = local.workspaces[terraform.workspace]
  workspaces = {
    "root-us-west-2" = {
      role        = "arn:aws:iam::472908028927:role/devops/cloud-admin"
      environment = "root"
    }
    "shared-us-west-2" = {
      role        = "arn:aws:iam::140253569749:role/devops/cloud-admin"
      environment = "shared"
    }
    "development-us-west-2" = {
      role        = "arn:aws:iam::793362518373:role/devops/cloud-admin"
      environment = "development"
    }
    "production-us-west-2" = {
      role        = "arn:aws:iam::101300729637:role/devops/cloud-admin"
      environment = "production"
    }
    "staging-us-west-2" = {
      role        = "arn:aws:iam::301712053745:role/devops/cloud-admin"
      environment = "staging"
    }
    "audit-us-west-2" = {
      role        = "arn:aws:iam::605289256863:role/devops/cloud-admin"
      environment = "audit"
    }
    "log-us-west-2" = {
      role        = "arn:aws:iam::957617154769:role/devops/cloud-admin"
      environment = "log"
    }
  }
}
