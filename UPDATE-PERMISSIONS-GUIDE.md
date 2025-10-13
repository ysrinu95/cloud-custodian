# Update IAM Permissions Guide

## Current Issue
The GitHub Actions role lacks the following permissions:
- `s3:PutEncryptionConfiguration` - for S3 bucket encryption
- `s3:PutBucketPublicAccessBlock` - for S3 public access blocking
- `logs:PutRetentionPolicy` - for CloudWatch logs retention
- `iam:CreatePolicy` - for creating IAM policies

## Solution Options

### Option 1: Re-run Bootstrap Workflow (Recommended)
1. Go to: https://github.com/ysrinu95/cloud-custodian/actions
2. Click "Bootstrap OIDC Authentication" workflow
3. Click "Run workflow"
4. Enter:
   - `confirm_bootstrap`: **bootstrap**
   - `cleanup_existing`: **leave unchecked**
5. Click "Run workflow"

This will update the existing IAM role with the new permissions.

### Option 2: Manual AWS CLI Update (If you have AWS access)
If you have AWS CLI configured with admin permissions, run:

```bash
# Update the CloudCustodianPolicy with new permissions
aws iam create-policy-version \
  --policy-arn arn:aws:iam::172327596604:policy/CloudCustodianPolicy \
  --policy-document file://terraform-bootstrap/updated-policy.json \
  --set-as-default
```

### Option 3: Temporary Workaround - Remove Additional Configurations
Remove the following resources from `terraform/main.tf` temporarily:
- `aws_s3_bucket_server_side_encryption_configuration`
- `aws_s3_bucket_public_access_block` 
- `retention_in_days` from CloudWatch log group
- `aws_iam_policy` resource

## After Permissions Update
Once the IAM role is updated with proper permissions:
1. Re-run the "Deploy Cloud Custodian Infrastructure" workflow
2. All resources should be created successfully
3. Add back any removed configurations if using Option 3

## Next Steps
After infrastructure is deployed:
1. Test Cloud Custodian policy validation
2. Deploy policies using the Cloud Custodian workflows
3. Monitor policy execution and compliance reports