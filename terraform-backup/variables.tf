# AWS Region
variable "aws_region" {
  description = "The AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

# GitHub Repository
variable "github_repository" {
  description = "GitHub repository in the format 'owner/repo'"
  type        = string
  default     = "ysrinu95/cloud-custodian"
}

# GitHub Actions Role Name
variable "github_actions_role_name" {
  description = "Name for the GitHub Actions IAM role"
  type        = string
  default     = "GitHubActions-CloudCustodian-Role"
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