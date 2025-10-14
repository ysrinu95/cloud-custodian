#!/bin/bash

# Bootstrap script for Terraform remote state setup
# With Terraform 1.6+, no DynamoDB table is needed for S3 state locking!
# Only need to verify the S3 bucket exists

set -e

echo "🚀 Verifying Terraform remote state infrastructure..."

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS CLI is not configured or credentials are invalid"
    echo "Please run 'aws configure' or set AWS environment variables"
    exit 1
fi

echo "✅ AWS credentials verified"

# Check if S3 bucket exists
if aws s3 ls "s3://ysr95-cloud-custodian-tf-bkt" &> /dev/null; then
    echo "✅ S3 bucket 'ysr95-cloud-custodian-tf-bkt' exists"
else
    echo "❌ S3 bucket 'ysr95-cloud-custodian-tf-bkt' does not exist"
    echo "Please create the bucket first or verify the bucket name"
    exit 1
fi

# Check Terraform version
TERRAFORM_VERSION=$(terraform version -json | jq -r '.terraform_version')
REQUIRED_VERSION="1.6.0"

if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$TERRAFORM_VERSION" | sort -V | head -n1)" = "$REQUIRED_VERSION" ]; then
    echo "✅ Terraform version $TERRAFORM_VERSION supports S3 native locking"
else
    echo "⚠️  Terraform version $TERRAFORM_VERSION detected"
    echo "   For S3 native locking, please upgrade to Terraform 1.6.0 or later"
    echo "   Current setup will work but may need DynamoDB for locking"
fi

echo ""
echo "✅ Bootstrap verification completed!"
echo ""
echo "📋 Infrastructure ready:"
echo "   - S3 Bucket: ysr95-cloud-custodian-tf-bkt (existing)"
echo "   - State Locking: S3 native (Terraform 1.6+) or DynamoDB fallback"
echo ""
echo "🔄 Next steps:"
echo "   1. Run 'terraform init' to initialize the S3 backend"
echo "   2. Run 'terraform plan' and 'terraform apply' for the main infrastructure"
echo ""
echo "🎉 No DynamoDB table needed with Terraform 1.6+ S3 native locking!"