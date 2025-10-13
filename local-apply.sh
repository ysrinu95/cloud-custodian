#!/bin/bash

# Local Terraform Apply Script
# Run this if you want to apply the infrastructure locally

echo "🔄 Configuring AWS credentials..."
# Make sure your AWS credentials are configured

echo "📁 Navigating to terraform directory..."
cd terraform

echo "🔄 Initializing Terraform..."
terraform init -upgrade \
  -backend-config="bucket=ysr95-cloud-custodian-tf-bkt" \
  -backend-config="key=terraform/cloud-custodian/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="encrypt=true"

echo "📝 Creating terraform.tfvars..."
cat > terraform.tfvars <<EOF
aws_region = "us-east-1"
github_repository = "ysrinu95/cloud-custodian"
github_actions_role_name = "GitHubActions-CloudCustodian-Role"
environment = "prod"
project_name = "cloud-custodian"
EOF

echo "📋 Running Terraform plan..."
terraform plan -out=tfplan

echo "🚀 Applying Terraform..."
terraform apply -auto-approve tfplan

echo "✅ Done! Your Cloud Custodian infrastructure is ready!"
terraform output