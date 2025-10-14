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

# Lambda Execution Role
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

# GitHub Repository
output "github_repository" {
  description = "GitHub repository"
  value       = var.github_repository
}