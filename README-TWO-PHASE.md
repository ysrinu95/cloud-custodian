# Two-Phase Cloud Custodian Setup

This repository implements a secure two-phase deployment approach for Cloud Custodian:

1. **Phase 1 (Bootstrap)**: Use access keys to create OIDC provider and IAM role
2. **Phase 2 (Operations)**: Use OIDC authentication for all Cloud Custodian operations

## 🎯 Architecture Overview

```
Phase 1: Bootstrap (Uses Access Keys)
├── terraform-bootstrap/
│   ├── Creates OIDC Provider
│   ├── Creates IAM Role
│   └── Attaches Cloud Custodian policies

Phase 2: Operations (Uses OIDC)
├── terraform/ (Cloud Custodian infrastructure)
│   ├── S3 bucket for outputs
│   ├── CloudWatch logs
│   ├── SNS notifications
│   └── Lambda execution roles
└── policies/ (Cloud Custodian policies)
```

## 🚀 Quick Start Guide

### Step 1: Bootstrap OIDC Authentication

1. **Ensure GitHub Secrets are configured**:
   - `ACCESS_KEY` - Your AWS Access Key ID
   - `SECRET_ACCESS_KEY` - Your AWS Secret Access Key

2. **Run Bootstrap Workflow**:
   - Go to Actions → "Bootstrap OIDC Authentication"
   - Click "Run workflow"
   - Type "bootstrap" in the confirmation field
   - Click "Run workflow"

3. **Configure GitHub Secret**:
   After bootstrap completes, add the new secret:
   - **Name**: `AWS_ROLE_ARN`
   - **Value**: (from bootstrap workflow output)

### Step 2: Deploy Cloud Custodian Infrastructure

1. **Run Main Deployment**:
   - Go to Actions → "Deploy Cloud Custodian Infrastructure"
   - Click "Run workflow" (will now use OIDC authentication)

### Step 3: Execute Cloud Custodian Policies

1. **Run Cloud Custodian Operations**:
   - Go to Actions → "Cloud Custodian Operations"
   - Choose action: validate, dryrun, or run
   - Click "Run workflow"

## 🔒 Security Benefits

### Before (Access Keys Only)
- ❌ Long-term AWS credentials in GitHub
- ❌ Broad permissions stored as secrets
- ❌ Risk of credential exposure
- ❌ Manual credential rotation

### After (OIDC Authentication)
- ✅ No long-term AWS credentials in GitHub
- ✅ Short-lived, scoped tokens
- ✅ AWS native identity federation
- ✅ Automatic token rotation
- ✅ Audit trail in AWS CloudTrail

## 📁 Directory Structure

```
.
├── .github/workflows/
│   ├── bootstrap-oidc.yml        # Phase 1: Bootstrap OIDC
│   ├── terraform.yml             # Phase 2: Main infrastructure
│   └── cloud-custodian.yml       # Phase 2: Policy operations
├── terraform-bootstrap/          # Phase 1 Terraform
│   ├── main.tf                   # OIDC provider and IAM role
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── terraform/                    # Phase 2 Terraform
│   ├── main.tf                   # Cloud Custodian infrastructure
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
└── policies/                     # Cloud Custodian policies
    ├── example-policies.yml
    └── README.md
```

## 🔄 Migration Path

### Current State: Using Access Keys
```yaml
# Current workflow authentication
- name: Configure AWS Credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    aws-access-key-id: ${{ secrets.ACCESS_KEY }}
    aws-secret-access-key: ${{ secrets.SECRET_ACCESS_KEY }}
```

### Target State: Using OIDC
```yaml
# New workflow authentication
- name: Configure AWS Credentials via OIDC
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
    aws-region: us-east-1
```

## ⚡ Workflow Details

### 1. Bootstrap OIDC Authentication (`bootstrap-oidc.yml`)
- **Trigger**: Manual dispatch with confirmation
- **Authentication**: Access keys (last time!)
- **Purpose**: Create OIDC provider and IAM role
- **Output**: Role ARN for GitHub secret

### 2. Deploy Cloud Custodian Infrastructure (`terraform.yml`)
- **Trigger**: Push to main, PR, manual dispatch
- **Authentication**: OIDC
- **Purpose**: Deploy Cloud Custodian supporting infrastructure
- **Resources**: S3 buckets, CloudWatch logs, SNS topics, Lambda roles

### 3. Cloud Custodian Operations (`cloud-custodian.yml`)
- **Trigger**: Manual dispatch
- **Authentication**: OIDC
- **Purpose**: Execute Cloud Custodian policies
- **Actions**: validate, dryrun, run

## 🛠️ Advanced Configuration

### Custom Policy Execution
```bash
# Run specific policy file
c7n-custodian run -s output/ policies/security-policies.yml

# Dry run with detailed output
c7n-custodian run --dryrun -v -s output/ policies/cost-optimization.yml
```

### Multi-Account Setup
For multi-account deployments, modify the IAM role trust policy to include additional accounts or use AWS Organizations.

### Notification Setup
Configure SNS topic subscriptions for policy execution notifications:
```bash
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:ACCOUNT:cloud-custodian-notifications \
  --protocol email \
  --notification-endpoint your-email@domain.com
```

## 🔍 Troubleshooting

### Bootstrap Issues
1. **Access denied**: Ensure ACCESS_KEY has IAM permissions
2. **OIDC provider exists**: Delete existing provider or import to Terraform
3. **Role name conflict**: Change `github_actions_role_name` variable

### OIDC Authentication Issues
1. **Role not found**: Ensure bootstrap completed successfully
2. **Permission denied**: Check role trust policy and permissions
3. **Token issues**: Verify repository name in trust policy

### Cloud Custodian Issues
1. **Policy validation fails**: Check YAML syntax and resource types
2. **Permission denied**: Ensure Lambda execution role has required permissions
3. **Output bucket access**: Verify S3 bucket permissions

## 📈 Monitoring and Observability

- **CloudWatch Logs**: `/aws/cloud-custodian/cloud-custodian`
- **S3 Outputs**: `ysr95-cloud-custodian-outputs-*`
- **SNS Notifications**: `cloud-custodian-notifications`
- **CloudTrail**: Monitor OIDC token usage

## 🔄 Next Steps After Setup

1. **Remove old secrets**: Delete `ACCESS_KEY` and `SECRET_ACCESS_KEY`
2. **Create custom policies**: Add your organization-specific policies
3. **Set up monitoring**: Configure CloudWatch alarms and SNS subscriptions
4. **Schedule policies**: Use GitHub Actions scheduling for regular execution

This setup provides a secure, scalable foundation for Cloud Custodian operations with modern OIDC authentication! 🎉