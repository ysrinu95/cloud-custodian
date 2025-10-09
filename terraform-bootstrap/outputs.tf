# OIDC Provider ARN
output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = aws_iam_openid_connect_provider.github.arn
}

# GitHub Actions Role ARN
output "github_actions_role_arn" {
  description = "ARN of the GitHub Actions IAM role"
  value       = aws_iam_role.github_actions.arn
  sensitive   = false
}

# GitHub Actions Role Name
output "github_actions_role_name" {
  description = "Name of the GitHub Actions IAM role"
  value       = aws_iam_role.github_actions.name
}

# Cloud Custodian Policy ARN
output "cloud_custodian_policy_arn" {
  description = "ARN of the Cloud Custodian IAM policy"
  value       = aws_iam_policy.cloud_custodian_policy.arn
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

# Instructions for next steps
output "next_steps" {
  description = "Instructions for configuring GitHub secrets"
  value = <<-EOT
    🎉 Bootstrap completed successfully!
    
    📋 Next Steps:
    1. Add the following GitHub repository secret:
       - Name: AWS_ROLE_ARN
       - Value: ${aws_iam_role.github_actions.arn}
    
    2. Update your GitHub Actions workflows to use OIDC authentication
    3. All future deployments will use OIDC instead of access keys
    
    🔒 Security: You can now remove the ACCESS_KEY and SECRET_ACCESS_KEY secrets from GitHub
  EOT
}