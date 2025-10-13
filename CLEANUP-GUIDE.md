# Manual AWS Resource Cleanup Guide

Follow these steps to destroy existing resources and set up remote state:

## Prerequisites
1. Install AWS CLI v2: Download from https://awscli.amazonaws.com/AWSCLIV2.msi
2. Configure AWS CLI: Run `aws configure` with your access keys
3. Terraform is already installed in your tools directory

## Step 1: Configure AWS CLI
```powershell
# Download and install AWS CLI manually if the script didn't work
# Then configure it
aws configure
# Enter your:
# - AWS Access Key ID
# - AWS Secret Access Key  
# - Default region (us-east-1)
# - Default output format (json)
```

## Step 2: Run the Cleanup Script
```powershell
cd "c:\United Techno\Git Repos\cloud-custodian"
.\cleanup-and-setup.ps1
```

## Step 3: Manual Cleanup (if script fails)
If the script doesn't work, manually delete these resources in AWS Console:

### IAM Resources to Delete:
1. **IAM Role**: `GitHubActions-CloudCustodian-Role`
   - Go to IAM > Roles
   - Search for "GitHubActions-CloudCustodian-Role"
   - Detach all policies first, then delete the role

2. **IAM Policy**: `CloudCustodianPolicy`
   - Go to IAM > Policies
   - Search for "CloudCustodianPolicy"
   - Delete the policy (make sure it's not attached to any roles)

3. **OIDC Provider**: GitHub OIDC Provider
   - Go to IAM > Identity providers
   - Look for provider with URL: `https://token.actions.githubusercontent.com`
   - Delete the provider

### S3 Bucket Creation:
Create bucket `ysr95-cloud-custodian-tf-bkt` with:
- Versioning enabled
- Server-side encryption enabled
- Public access blocked

## Step 4: Initialize Terraform with Remote State
```powershell
cd "c:\United Techno\Git Repos\cloud-custodian\terraform-bootstrap"
$env:PATH = "$env:USERPROFILE\tools;$env:PATH"  # Add terraform to PATH
terraform init
```

## Step 5: Deploy Fresh Resources
```powershell
# Review the plan
terraform plan

# Apply the changes
terraform apply
```

## Step 6: Update GitHub Secrets
After successful deployment, update your GitHub repository secrets:
- Remove: `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` 
- Add: `AWS_ROLE_ARN` with the output value from terraform apply

## Verification
Your resources will now be managed with proper Terraform state in S3, enabling:
- State locking
- Team collaboration
- State versioning and backup
- Proper resource tracking

## Troubleshooting
- If terraform init fails, ensure S3 bucket exists and you have proper permissions
- If AWS CLI commands fail, verify `aws sts get-caller-identity` works
- Check AWS credentials have sufficient IAM permissions for all operations