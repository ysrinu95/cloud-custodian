# AWS Provider Configuration
terraform {
  required_version = ">= 1.6"

  # S3 Backend for Remote State
  backend "s3" {
    bucket  = "ysr95-cloud-custodian-tf-bkt"
    key     = "terraform/cloud-custodian/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.45"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Support for both local profile and web identity for CI/CD
  profile = var.aws_profile
  dynamic "assume_role_with_web_identity" {
    for_each = var.aws_profile == null && var.github_actions_web_identity_role != null ? ["true"] : []
    content {
      role_arn                = var.github_actions_web_identity_role
      web_identity_token_file = "/tmp/web-identity-token"
    }
  }

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
      Repository  = var.github_repository
    }
  }

  ignore_tags {
    key_prefixes = [
      "c7n:"
    ]
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Reference existing OIDC provider (created by bootstrap)
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# Reference existing IAM role (created by bootstrap)
data "aws_iam_role" "github_actions" {
  name = var.github_actions_role_name
}

# S3 Bucket for Cloud Custodian outputs and logs
resource "aws_s3_bucket" "custodian_outputs" {
  bucket = "ysr95-cloud-custodian-outputs-${random_string.bucket_suffix.result}"

  # Temporarily removed tags due to permission issues
  # Will be added back after IAM permissions are updated
}

# Random suffix for bucket name uniqueness
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Enable versioning on the outputs bucket
resource "aws_s3_bucket_versioning" "custodian_outputs" {
  bucket = aws_s3_bucket.custodian_outputs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "custodian_outputs" {
  bucket = aws_s3_bucket.custodian_outputs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "custodian_outputs" {
  bucket = aws_s3_bucket.custodian_outputs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudWatch Log Group for Cloud Custodian logs
resource "aws_cloudwatch_log_group" "custodian_logs" {
  name              = "/aws/cloud-custodian/${var.project_name}"
  retention_in_days = 30

  # Temporarily removed tags due to permission issues
  # Will be added back after IAM permissions are updated
}

# SNS Topic for Cloud Custodian notifications
resource "aws_sns_topic" "custodian_notifications" {
  name = "cloud-custodian-notifications"
}

# Enterprise logging bucket (conditionally created)
resource "aws_s3_bucket" "custodian_logs" {
  count  = var.enable_enterprise_features ? 1 : 0
  bucket = "${var.project_name}-logs-${random_string.bucket_suffix.result}"
}

# Security settings for logging bucket
resource "aws_s3_bucket_public_access_block" "custodian_logs" {
  count  = var.enable_enterprise_features ? 1 : 0
  bucket = aws_s3_bucket.custodian_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Server-side encryption for logging bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "custodian_logs" {
  count  = var.enable_enterprise_features ? 1 : 0
  bucket = aws_s3_bucket.custodian_logs[0].bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle policy for logging bucket (keep 90 days worth of logs)
resource "aws_s3_bucket_lifecycle_configuration" "custodian_logs" {
  count  = var.enable_enterprise_features ? 1 : 0
  bucket = aws_s3_bucket.custodian_logs[0].id

  rule {
    id     = "prune"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }
  }
}

# Cloud Custodian execution role (supports both Lambda and direct execution)
resource "aws_iam_role" "custodian_execution" {
  name = "CloudCustodian-ExecutionRole"
  path = "/cloud-custodian/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaAssumeRole"
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
      # Allow GitHub Actions to assume this role for direct policy execution
      {
        Sid    = "AllowGitHubActionsAssumeRole"
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.github.arn
        }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:*"
          }
        }
      }
    ]
  })

  tags = {
    "c7n-exception:iam-admin" = ""
    "c7n-exception:unused"    = ""
  }
}

# Legacy Lambda execution role for backward compatibility
resource "aws_iam_role" "custodian_lambda_execution" {
  name = "CloudCustodian-Lambda-ExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Administrative access for Cloud Custodian execution role
resource "aws_iam_role_policy_attachment" "custodian_admin_access" {
  role       = aws_iam_role.custodian_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Attach basic Lambda execution policy to both roles
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.custodian_lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "custodian_lambda_basic_execution" {
  role       = aws_iam_role.custodian_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for Lambda functions created by Cloud Custodian
resource "aws_iam_policy" "custodian_lambda_policy" {
  name        = "CloudCustodian-Lambda-Policy"
  description = "Policy for Lambda functions created by Cloud Custodian"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:*",
          "s3:*",
          "sns:Publish",
          "sqs:SendMessage",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "cloudwatch:PutMetricData",
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach custom policy to both roles
resource "aws_iam_role_policy_attachment" "lambda_custodian_policy" {
  role       = aws_iam_role.custodian_lambda_execution.name
  policy_arn = aws_iam_policy.custodian_lambda_policy.arn
}

resource "aws_iam_role_policy_attachment" "custodian_execution_policy" {
  role       = aws_iam_role.custodian_execution.name
  policy_arn = aws_iam_policy.custodian_lambda_policy.arn
}