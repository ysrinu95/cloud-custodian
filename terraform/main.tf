# AWS Provider Configuration
terraform {
  required_version = ">= 1.6"
  
  # S3 Backend for Remote State with native locking
  backend "s3" {
    bucket  = "ysr95-cloud-custodian-tf-bkt"
    key     = "terraform/cloud-custodian/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
    
    # Enable S3 native state locking (no DynamoDB required)
    use_lockfile = true
  }
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

provider "aws" {
  region = var.aws_region
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

  tags = {
    Name        = "Cloud Custodian Outputs"
    Purpose     = "Cloud-Custodian-Outputs"
    ManagedBy   = "Terraform"
    Environment = var.environment
  }
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

  tags = {
    Name        = "Cloud Custodian Logs"
    Purpose     = "Cloud-Custodian-Logging"
    ManagedBy   = "Terraform"
    Environment = var.environment
  }
}

# SNS Topic for Cloud Custodian notifications
resource "aws_sns_topic" "custodian_notifications" {
  name = "cloud-custodian-notifications"

  tags = {
    Name        = "Cloud Custodian Notifications"
    Purpose     = "Cloud-Custodian-Notifications"
    ManagedBy   = "Terraform"
    Environment = var.environment
  }
}

# Lambda execution role for Cloud Custodian serverless policies
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

  tags = {
    Name        = "Cloud Custodian Lambda Execution Role"
    Purpose     = "Cloud-Custodian-Lambda"
    ManagedBy   = "Terraform"
    Environment = var.environment
  }
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
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

  tags = {
    Name        = "Cloud Custodian Lambda Policy"
    Purpose     = "Cloud-Custodian-Lambda"
    ManagedBy   = "Terraform"
    Environment = var.environment
  }
}

# Attach custom policy to Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_custodian_policy" {
  role       = aws_iam_role.custodian_lambda_execution.name
  policy_arn = aws_iam_policy.custodian_lambda_policy.arn
}