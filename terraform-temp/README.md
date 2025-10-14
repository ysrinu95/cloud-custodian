# Terraform Infrastructure for Cloud Custodian

This directory contains Terraform configuration to set up AWS IAM Identity Provider and roles for Cloud Custodian operations via GitHub Actions.

## What This Creates

1. **GitHub OIDC Identity Provider** - Enables secure authentication from GitHub Actions to AWS
2. **IAM Role for GitHub Actions** - Role that GitHub Actions can assume
3. **Cloud Custodian IAM Policy** - Comprehensive permissions for Cloud Custodian operations
4. **Policy Attachments** - Links the policy to the GitHub Actions role
5. **S3 Backend Configuration** - Remote state stored in existing `ysr95-cloud-custodian-tf-bkt` bucket
6. **S3 Native State Locking** - Prevents concurrent Terraform runs using S3 built-in locking (Terraform 1.6+)

## Prerequisites

1. AWS CLI configured with appropriate credentials
2. Terraform installed (>= 1.6.0 for S3 native locking)
3. GitHub repository with secrets configured
4. S3 bucket `ysr95-cloud-custodian-tf-bkt` already exists in AWS (✅ confirmed)

## Setup Instructions

### 1. Verify Prerequisites (One-time setup)

With Terraform 1.6+, no DynamoDB table is needed for S3 state locking!

**Option A: Using the verification script (recommended):**
```bash
./bootstrap.sh
```

**Option B: Manual verification:**
```bash
# Verify S3 bucket exists
aws s3 ls s3://ysr95-cloud-custodian-tf-bkt

# Check Terraform version (should be 1.6.0 or later)
terraform version
```

**Note**: The S3 bucket `ysr95-cloud-custodian-tf-bkt` already exists. No DynamoDB table is required with Terraform 1.6+ S3 native locking!

### 2. Configure Variables

Copy the example variables file and customize it:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your specific values:

```hcl
aws_region = "us-east-1"
github_repository = "ysrinu95/cloud-custodian"
github_actions_role_name = "GitHubActions-CloudCustodian-Role"
environment = "dev"
project_name = "cloud-custodian"
```

### 3. Initialize Terraform with S3 Backend

```bash
terraform init
```

This will configure the S3 backend and migrate any existing local state.

### 4. Plan the Deployment

```bash
terraform plan
```

### 5. Apply the Configuration

```bash
terraform apply
```

### 5. Note the Outputs

After successful deployment, note these important outputs:
- `github_actions_role_arn` - Use this in GitHub Actions workflows
- `github_oidc_provider_arn` - ARN of the OIDC provider

## Using with GitHub Actions

### Option 1: With OIDC (Recommended - No long-term credentials)

Create a GitHub Actions workflow that uses the OIDC role:

```yaml
name: Cloud Custodian Deploy
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: us-east-1
          
      - name: Test AWS connection
        run: aws sts get-caller-identity
        
      - name: Run Cloud Custodian
        run: |
          # Your Cloud Custodian commands here
          custodian run -s output/ policies/
```

Add the role ARN to your GitHub repository secrets:
- Secret name: `AWS_ROLE_ARN`
- Secret value: The `github_actions_role_arn` output from Terraform

### Option 2: With Access Keys (Your Current Setup)

If you prefer to continue using access keys, the IAM policy created by this Terraform configuration will provide the necessary permissions for your existing GitHub Actions setup.

## Cloud Custodian Permissions

The IAM policy includes comprehensive permissions for:

- **EC2**: Instance management, tagging, start/stop/terminate
- **S3**: Bucket and object operations for outputs and logs
- **Lambda**: Function creation and management for serverless policies
- **CloudWatch**: Events and logs for monitoring and triggers
- **IAM**: Role management for Lambda execution
- **SNS/SQS**: Notifications and messaging
- **CloudFormation**: Infrastructure management
- **Config**: Compliance monitoring
- **CloudTrail**: Auditing capabilities
- **Cost Explorer**: Cost analysis
- **Resource Groups Tagging**: Resource organization

## Security Considerations

1. **OIDC Trust Policy**: Restricts access to your specific GitHub repository
2. **Least Privilege**: Permissions are scoped to Cloud Custodian operations
3. **Resource-level Permissions**: Some permissions are applied at resource level where possible
4. **Service-linked Roles**: Allows creation of AWS service-linked roles as needed

## Cleanup

To destroy the created resources:

```bash
terraform destroy
```

## 🔒 Remote State Configuration

Your Terraform state will now be:
- **Stored in**: `s3://ysr95-cloud-custodian-tf-bkt/terraform/cloud-custodian/terraform.tfstate`
- **Locked with**: S3 native locking (Terraform 1.6+ feature)
- **Encrypted**: Yes (AES256)
- **Region**: us-east-1

## 🎉 Advantages of S3 Native Locking

- ✅ **No DynamoDB required** - Simpler infrastructure
- ✅ **Lower costs** - No DynamoDB charges
- ✅ **Built-in reliability** - Native S3 locking mechanism  
- ✅ **Easier setup** - One less resource to manage
- ✅ **Better performance** - Direct S3 integration

This setup ensures your Terraform state is secure, shared, and protected from concurrent modifications without the complexity of DynamoDB!

## Troubleshooting

### Common Issues

1. **OIDC Provider Already Exists**: If you get an error about the OIDC provider already existing, you can import it:
   ```bash
   terraform import aws_iam_openid_connect_provider.github arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com
   ```

2. **Permission Denied**: Ensure your AWS credentials have sufficient permissions to create IAM resources

3. **GitHub Actions Can't Assume Role**: Check that the trust policy matches your repository name exactly

## Next Steps

1. Deploy this Terraform configuration
2. Update your GitHub repository secrets with the role ARN
3. Create Cloud Custodian policies in a `policies/` directory
4. Set up GitHub Actions workflows to run your policies

For Cloud Custodian-specific guidance, refer to the main repository documentation and the `.github/copilot-instructions.md` file.