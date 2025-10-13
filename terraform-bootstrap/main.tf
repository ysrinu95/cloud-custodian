# Bootstrap Terraform Configuration
# This creates only the OIDC provider and IAM role using access keys
# After this runs successfully, all other operations will use OIDC

terraform {
  required_version = ">= 1.6"
  
  # S3 backend for remote state management
  backend "s3" {
    bucket  = "ysr95-cloud-custodian-tf-bkt"
    key     = "terraform/bootstrap/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# GitHub OIDC Identity Provider
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com",
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = {
    Name        = "GitHub-OIDC-Provider"
    Purpose     = "Cloud-Custodian-CI"
    Repository  = var.github_repository
    ManagedBy   = "Terraform"
  }
}

# IAM Role for GitHub Actions
resource "aws_iam_role" "github_actions" {
  name = var.github_actions_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
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
    Name        = var.github_actions_role_name
    Purpose     = "Cloud-Custodian-CI"
    Repository  = var.github_repository
    ManagedBy   = "Terraform"
  }
}

# Cloud Custodian specific IAM policies
resource "aws_iam_policy" "cloud_custodian_policy" {
  name        = "CloudCustodianPolicy"
  description = "IAM policy for Cloud Custodian operations"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          # EC2 permissions for resource discovery and management
          "ec2:Describe*",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:TerminateInstances",
          "ec2:ModifyInstanceAttribute",
          
          # S3 permissions for policy outputs and logs
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketPolicy",
          "s3:GetBucketVersioning",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject",
          "s3:PutBucketPolicy",
          "s3:PutBucketVersioning",
          "s3:DeleteObject",
          
          # Lambda permissions for serverless policies
          "lambda:CreateFunction",
          "lambda:DeleteFunction",
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration",
          "lambda:InvokeFunction",
          "lambda:ListFunctions",
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:AddPermission",
          "lambda:RemovePermission",
          "lambda:GetPolicy",
          "lambda:PutProvisionedConcurrencyConfig",
          "lambda:DeleteProvisionedConcurrencyConfig",
          
          # CloudWatch Events for Lambda triggers
          "events:PutRule",
          "events:DeleteRule",
          "events:DescribeRule",
          "events:PutTargets",
          "events:RemoveTargets",
          "events:ListTargetsByRule",
          
          # CloudWatch Logs
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DeleteLogGroup",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents",
          "logs:GetLogEvents",
          "logs:FilterLogEvents",
          
          # IAM permissions for Lambda execution roles
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:PassRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          
          # SNS for notifications
          "sns:CreateTopic",
          "sns:DeleteTopic",
          "sns:GetTopicAttributes",
          "sns:ListTopics",
          "sns:Publish",
          "sns:Subscribe",
          "sns:Unsubscribe",
          "sns:SetTopicAttributes",
          
          # SQS for message queuing
          "sqs:CreateQueue",
          "sqs:DeleteQueue",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ListQueues",
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:SetQueueAttributes",
          
          # Config for compliance monitoring
          "config:DescribeConfigRules",
          "config:DescribeComplianceByConfigRule",
          "config:GetComplianceDetailsByConfigRule",
          "config:PutConfigRule",
          "config:DeleteConfigRule",
          
          # CloudTrail for auditing
          "cloudtrail:DescribeTrails",
          "cloudtrail:GetTrailStatus",
          "cloudtrail:LookupEvents",
          
          # Cost and billing
          "ce:GetCostAndUsage",
          "ce:GetUsageReport",
          
          # Support for resource tagging
          "tag:GetResources",
          "tag:TagResources",
          "tag:UntagResources",
          
          # STS for identity verification
          "sts:GetCallerIdentity",
          "sts:AssumeRole"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole"
        ]
        Resource = "arn:aws:iam::*:role/aws-service-role/*"
      }
    ]
  })

  tags = {
    Name        = "CloudCustodianPolicy"
    Purpose     = "Cloud-Custodian-Operations"
    ManagedBy   = "Terraform"
  }
}

# Attach the Cloud Custodian policy to the GitHub Actions role
resource "aws_iam_role_policy_attachment" "github_actions_cloud_custodian" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.cloud_custodian_policy.arn
}

# Optional: Attach AWS managed policies for additional permissions
resource "aws_iam_role_policy_attachment" "github_actions_readonly" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}