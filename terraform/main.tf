# =====================================================
# TERRAFORM CONFIGURATION
# =====================================================

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

# =====================================================
# PROVIDERS
# =====================================================

provider "aws" {
  region = var.aws_region

  # Support for local profile
  profile = var.aws_profile

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
    }
  }

  ignore_tags {
    key_prefixes = [
      "c7n:"
    ]
  }
}

# =====================================================
# VARIABLES
# =====================================================

# AWS Region
variable "aws_region" {
  description = "The AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

# AWS Profile (for local development)
variable "aws_profile" {
  description = "Local AWS profile to use when running locally"
  type        = string
  default     = null
}

# Environment
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

# Project Name
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "cloud-custodian"
}

# Email for notifications
variable "notification_email" {
  description = "Email address for notifications"
  type        = string
  default     = "cloudadmin@yourcompany.com"
}

# =====================================================
# DATA SOURCES
# =====================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# =====================================================
# RANDOM RESOURCES
# =====================================================

# Random suffix for bucket name uniqueness
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# =====================================================
# S3 RESOURCES
# =====================================================

# S3 Bucket for Cloud Custodian outputs and logs
resource "aws_s3_bucket" "custodian_outputs" {
  bucket = "ysr95-cloud-custodian-outputs-${random_string.bucket_suffix.result}"
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

# =====================================================
# CLOUDWATCH RESOURCES
# =====================================================

# CloudWatch Log Group for Cloud Custodian logs
resource "aws_cloudwatch_log_group" "custodian_logs" {
  name              = "/aws/cloud-custodian/${var.project_name}"
  retention_in_days = 30
}

# =====================================================
# SNS RESOURCES
# =====================================================

# SNS Topic for Cloud Custodian notifications
resource "aws_sns_topic" "custodian_notifications" {
  name = "cloud-custodian-notifications"
}

# =====================================================
# SQS RESOURCES
# =====================================================

# SQS Queue for Cloud Custodian mailer
resource "aws_sqs_queue" "custodian_mailer" {
  name                      = "custodian-mailer-queue"
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 1209600 # 14 days
}

# =====================================================
# SES RESOURCES
# =====================================================

# SES Email Identity for notifications
resource "aws_ses_email_identity" "custodian_notifications" {
  count = var.notification_email != null ? 1 : 0
  email = var.notification_email
}

# =====================================================
# IAM RESOURCES
# =====================================================

# Cloud Custodian execution role
resource "aws_iam_role" "custodian_execution" {
  name = "CloudCustodian-ExecutionRole"
  path = "/cloud-custodian/"

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

# Lambda execution role (for backward compatibility)
resource "aws_iam_role" "custodian_lambda_execution" {
  name = "CloudCustodian-Lambda-ExecutionRole"
  path = "/cloud-custodian/"

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

# Basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "custodian_lambda_basic_execution" {
  role       = aws_iam_role.custodian_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "custodian_lambda_execution_basic" {
  role       = aws_iam_role.custodian_lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for Cloud Custodian
resource "aws_iam_policy" "custodian_policy" {
  name        = "CloudCustodian-Policy"
  description = "Policy for Cloud Custodian execution"

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

# Attach policy to roles
resource "aws_iam_role_policy_attachment" "custodian_execution_policy" {
  role       = aws_iam_role.custodian_execution.name
  policy_arn = aws_iam_policy.custodian_policy.arn
}

resource "aws_iam_role_policy_attachment" "custodian_lambda_policy" {
  role       = aws_iam_role.custodian_lambda_execution.name
  policy_arn = aws_iam_policy.custodian_policy.arn
}

# =====================================================
# OUTPUTS
# =====================================================

# Cloud Custodian S3 Bucket
output "custodian_outputs_bucket" {
  description = "S3 bucket for Cloud Custodian outputs"
  value       = aws_s3_bucket.custodian_outputs.bucket
}

# Cloud Custodian Log Group
output "custodian_log_group" {
  description = "CloudWatch log group for Cloud Custodian"
  value       = aws_cloudwatch_log_group.custodian_logs.name
}

# SNS Topic for notifications
output "custodian_sns_topic_arn" {
  description = "SNS topic ARN for Cloud Custodian notifications"
  value       = aws_sns_topic.custodian_notifications.arn
}

# SQS Queue URL for mailer
output "custodian_mailer_queue_url" {
  description = "SQS queue URL for Cloud Custodian mailer"
  value       = aws_sqs_queue.custodian_mailer.url
}

# Primary Cloud Custodian execution role
output "custodian_execution_role_arn" {
  description = "Primary IAM role ARN for Cloud Custodian execution"
  value       = aws_iam_role.custodian_execution.arn
}

# Legacy Lambda Execution Role
output "custodian_lambda_role_arn" {
  description = "IAM role ARN for Cloud Custodian Lambda functions"
  value       = aws_iam_role.custodian_lambda_execution.arn
}

# AWS Account ID
output "aws_account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

# AWS Region
output "aws_region" {
  description = "AWS Region"
  value       = data.aws_region.current.name
}

# =====================================================
# IAM RESOURCES
# =====================================================

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
      }
    ]
  })

  tags = {
    "c7n-exception:iam-admin" = ""
    "c7n-exception:unused"    = ""
  }
}

# Legacy Lambda execution role (for backward compatibility)
resource "aws_iam_role" "custodian_lambda_execution" {
  name = "CloudCustodian-Lambda-ExecutionRole"
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
      }
    ]
  })

  tags = {
    "c7n-exception:iam-admin" = ""
    "c7n-exception:unused"    = ""
  }
}

# Attach AWS managed policy for Lambda basic execution
resource "aws_iam_role_policy_attachment" "custodian_lambda_basic_execution" {
  role       = aws_iam_role.custodian_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "custodian_lambda_execution_basic" {
  role       = aws_iam_role.custodian_lambda_execution.name
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

# =====================================================
# OUTPUTS
# =====================================================

# OIDC Provider ARN (from bootstrap)
output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = data.aws_iam_openid_connect_provider.github.arn
}

# GitHub Actions Role ARN (from bootstrap)
output "github_actions_role_arn" {
  description = "ARN of the GitHub Actions IAM role"
  value       = data.aws_iam_role.github_actions.arn
}

# GitHub Actions Role Name (from bootstrap)
output "github_actions_role_name" {
  description = "Name of the GitHub Actions IAM role"
  value       = data.aws_iam_role.github_actions.name
}

# Cloud Custodian S3 Bucket
output "custodian_outputs_bucket" {
  description = "S3 bucket for Cloud Custodian outputs"
  value       = aws_s3_bucket.custodian_outputs.bucket
}

# Cloud Custodian Log Group
output "custodian_log_group" {
  description = "CloudWatch log group for Cloud Custodian"
  value       = aws_cloudwatch_log_group.custodian_logs.name
}

# SNS Topic for notifications
output "custodian_sns_topic_arn" {
  description = "SNS topic ARN for Cloud Custodian notifications"
  value       = aws_sns_topic.custodian_notifications.arn
}

# Legacy Lambda Execution Role
output "custodian_lambda_role_arn" {
  description = "IAM role ARN for Cloud Custodian Lambda functions"
  value       = aws_iam_role.custodian_lambda_execution.arn
}

# Primary Cloud Custodian execution role
output "custodian_execution_role_arn" {
  description = "Primary IAM role ARN for Cloud Custodian execution"
  value       = aws_iam_role.custodian_execution.arn
}

# Enterprise logging bucket (conditional)
output "custodian_logs_bucket" {
  description = "S3 bucket for Cloud Custodian logs (enterprise feature)"
  value       = var.enable_enterprise_features ? aws_s3_bucket.custodian_logs[0].bucket : null
}

# SQS Queue URL for mailer (enterprise feature)
output "custodian_mailer_queue_url" {
  description = "SQS queue URL for Cloud Custodian mailer (enterprise feature)"
  value       = var.enable_enterprise_features ? aws_sqs_queue.custodian_mailer[0].url : null
}

# SES Email Identity (enterprise feature)
output "custodian_notification_email" {
  description = "SES email identity for Cloud Custodian notifications"
  value       = var.enable_enterprise_features && var.notification_email != null ? aws_ses_email_identity.custodian_notifications[0].email : null
}

# AWS Account ID
output "aws_account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

# AWS Region
output "aws_region" {
  description = "AWS Region"
  value       = data.aws_region.current.name
}

# GitHub Repository
output "github_repository" {
  description = "GitHub repository"
  value       = var.github_repository
}