# Cloud Custodian Deployment Workflows

This directory contains comprehensive GitHub Actions workflows for deploying and managing Cloud Custodian policies across multiple AWS accounts.

## 🚀 Quick Start

### Manual Deployment via GitHub Actions

1. **Navigate to Actions tab** in your GitHub repository
2. **Select "Deploy Cloud Custodian Policies"** workflow
3. **Click "Run workflow"** and configure:
   - **Deployment Type**: Choose what to deploy
   - **Target Accounts**: Specify which accounts (or leave empty for all)
   - **AWS Regions**: Target regions (default: us-east-1)
   - **Dry Run**: Test deployment without making changes

### Local Validation

Before deploying, validate your policies locally:

```bash
# Validate all policies
c7n/scripts/validate-policies.sh

# Validate specific policy file
c7n/scripts/validate-policies.sh -p policies/user-security.yml

# Validate for specific account and region
c7n/scripts/validate-policies.sh -a development -r us-west-2 -v
```

## 📋 Available Workflows

### 1. Cloud Custodian Policies (`cloud-custodian-policies.yml`)

**Comprehensive multi-account policy deployment workflow**

**Triggers:**
- Manual dispatch (workflow_dispatch)
- Pull request (validation only)
- Push to main branch (auto-deployment)

**Features:**
- ✅ **Policy Validation**: Syntax, schema, and dry-run validation
- 🔍 **Change Detection**: Only deploy updated policies using c7n-policystream
- 🎯 **Multi-Account Deployment**: Deploy across 7 AWS accounts (development, staging, production, shared, audit, log, root)
- 🔐 **OIDC Authentication**: Secure, credential-less AWS access
- 📊 **Matrix Strategy**: Parallel deployment across accounts
- 🧹 **Cleanup Support**: Remove obsolete policies and resources
- 📧 **Mailer Integration**: Deploy notification system
- 📈 **Comprehensive Reporting**: Detailed summaries and artifacts

**Input Parameters:**
- `deployment_type`: What to deploy (deploy-updated, deploy-all, deploy-mailer, cleanup)
- `target_accounts`: Comma-separated account list (empty = all accounts)
- `regions`: Target AWS regions (default: us-east-1)
- `dry_run`: Test mode without making changes

**Example Usage:**
```yaml
# Deploy updated policies to development and staging
deployment_type: deploy-updated
target_accounts: development,staging
regions: us-east-1,us-west-2
dry_run: false
```

### 2. Cloud Custodian Infrastructure (`cloud-custodian-infra.yml`)

**Terraform-based infrastructure deployment**

**Features:**
- 🏗️ **Infrastructure as Code**: Deploy foundational AWS resources
- 🔄 **State Management**: Terraform state handling
- 🔐 **Security**: IAM roles, policies, and permissions
- 📦 **Bootstrap Support**: Initial account setup

### 3. Infrastructure Validation (`validate-infrastructure.yml`)

**Validate Terraform configurations**

**Features:**
- ✅ **Terraform Validation**: Syntax and configuration checks
- 🔍 **Security Scanning**: Detect security issues
- 📊 **Plan Generation**: Review infrastructure changes

## 🎯 Deployment Types

### `deploy-updated`
Deploy only policies that have changed since the last deployment:
- Uses `c7n-policystream` for change detection
- Efficient for frequent updates
- Recommended for development and staging

### `deploy-all` 
Deploy all policies regardless of changes:
- Complete policy refresh
- Use for initial deployments or major updates
- Recommended for production releases

### `deploy-mailer`
Deploy the Cloud Custodian mailer system:
- Email and Slack notifications
- SQS queue processing
- Only deploys to shared account

### `cleanup`
Remove obsolete policies and resources:
- Clean up deleted policy files
- Remove unused Lambda functions
- Garbage collection for cloud resources

## 🏗️ Architecture

### Account Strategy
```
📁 AWS Organization
├── 🔧 development     # Dev environment
├── 🧪 staging         # Staging environment  
├── 🚀 production      # Production environment
├── 🤝 shared          # Shared services (mailer, etc.)
├── 🔍 audit           # Audit and compliance
├── 📝 log             # Centralized logging
└── 👑 root            # Organization root account
```

### Deployment Flow
```
1. 🔍 Validation
   ├── Syntax checking
   ├── Schema validation
   └── Dry-run testing

2. 🎯 Target Selection
   ├── Account filtering
   ├── Region selection
   └── Change detection

3. 🚀 Deployment
   ├── Parallel execution
   ├── Error handling
   └── Progress tracking

4. 📊 Reporting
   ├── Success/failure status
   ├── Resource summaries
   └── Artifact collection
```

## 🔧 Configuration

### Required Secrets

Configure these in GitHub repository secrets:

```bash
# OIDC Configuration
AWS_ROLE_ARN_DEVELOPMENT    # arn:aws:iam::ACCOUNT:role/github-actions-role
AWS_ROLE_ARN_STAGING        # arn:aws:iam::ACCOUNT:role/github-actions-role
AWS_ROLE_ARN_PRODUCTION     # arn:aws:iam::ACCOUNT:role/github-actions-role
AWS_ROLE_ARN_SHARED         # arn:aws:iam::ACCOUNT:role/github-actions-role
AWS_ROLE_ARN_AUDIT          # arn:aws:iam::ACCOUNT:role/github-actions-role
AWS_ROLE_ARN_LOG            # arn:aws:iam::ACCOUNT:role/github-actions-role
AWS_ROLE_ARN_ROOT           # arn:aws:iam::ACCOUNT:role/github-actions-role

# OIDC Provider
AWS_OIDC_ROLE_ARN          # GitHub OIDC role ARN
```

### Account Configuration

Update `c7n/accounts.yml` with your AWS account details:

```yaml
accounts:
  - name: development
    account_id: "123456789012"
    role: "OrganizationAccountAccessRole"
    regions: ["us-east-1", "us-west-2"]
  - name: staging
    account_id: "123456789013"
    role: "OrganizationAccountAccessRole"
    regions: ["us-east-1", "us-west-2"]
  # ... additional accounts
```

## 📚 Policy Development

### Directory Structure
```
c7n/
├── policies/
│   ├── user-compliance.yml     # Compliance policies
│   ├── user-security.yml       # Security policies
│   ├── user-cost-optimization.yml # Cost management
│   └── user-realtime.yml       # Real-time monitoring
├── scripts/
│   ├── deploy-policies.sh      # Deploy all policies
│   ├── deploy-updated-policies.sh # Deploy changed policies
│   ├── deploy-mailer.sh        # Deploy mailer
│   ├── clean-removed-policies.sh # Cleanup
│   └── validate-policies.sh    # Local validation
└── accounts.yml                # Account configuration
```

### Policy Best Practices

1. **Use descriptive names**: Make policy purposes clear
2. **Include metadata**: Add descriptions and tags
3. **Test locally first**: Use `validate-policies.sh`
4. **Start with dry-run**: Test in development accounts
5. **Gradual rollout**: Development → Staging → Production

### Example Policy Structure
```yaml
policies:
  - name: ec2-untagged-instances
    description: Find and tag untagged EC2 instances
    resource: aws.ec2
    filters:
      - "tag:Environment": absent
    actions:
      - type: tag
        key: Environment
        value: "unknown"
      - type: notify
        template: default.html
        subject: "Untagged EC2 Instance Found"
```

## 🔍 Monitoring and Troubleshooting

### Workflow Monitoring

1. **GitHub Actions UI**: Monitor real-time execution
2. **Step Summaries**: Review deployment results
3. **Artifacts**: Download detailed logs and reports
4. **CloudWatch Logs**: Check Lambda execution logs

### Common Issues

**Authentication Failures:**
- Verify OIDC role configuration
- Check AWS account permissions
- Validate role ARNs in secrets

**Policy Validation Errors:**
- Run local validation first
- Check YAML syntax
- Verify resource names and filters

**Deployment Failures:**
- Review CloudWatch logs
- Check IAM permissions
- Verify account configuration

### Debugging Commands

```bash
# Local validation with verbose output
c7n/scripts/validate-policies.sh -v

# Test specific account deployment
c7n/scripts/deploy-policies.sh -a development -d

# Check policy differences
c7n-policystream diff --config c7n/policies/

# Validate single policy
custodian validate c7n/policies/user-security.yml
```

## 🚀 Advanced Usage

### Custom Deployment Scripts

The workflow system is built on reusable scripts in `c7n/scripts/`:

- `validate-policies.sh`: Comprehensive validation
- `deploy-policies.sh`: Full deployment
- `deploy-updated-policies.sh`: Incremental deployment  
- `deploy-mailer.sh`: Mailer deployment
- `clean-removed-policies.sh`: Resource cleanup

### Integration with External Systems

**Slack Notifications:**
Configure webhook URLs in mailer configuration

**SIEM Integration:**
Forward CloudWatch logs to security systems

**Cost Management:**
Integrate with AWS Cost Explorer and Budgets

### Multi-Region Deployment

The workflows support multi-region deployment:

```yaml
# Deploy to multiple regions
regions: us-east-1,us-west-2,eu-west-1
```

Region-specific policies can be created using filters:

```yaml
policies:
  - name: us-east-1-specific-policy
    resource: aws.ec2
    region: us-east-1
    # ... policy definition
```

## 📞 Support

For issues and questions:

1. **Check workflow logs** in GitHub Actions
2. **Review policy validation** with local tools  
3. **Verify configuration** in accounts.yml
4. **Check AWS permissions** and OIDC setup
5. **Consult Cloud Custodian documentation**: https://cloudcustodian.io/

## 🔄 Migration from Bitbucket

This workflow system is designed to replicate and enhance the functionality from your existing Bitbucket pipeline:

✅ **Feature Parity**: All Bitbucket features migrated
✅ **Enhanced Validation**: More comprehensive testing
✅ **Better Reporting**: Detailed summaries and artifacts
✅ **Improved Flexibility**: More deployment options
✅ **GitHub Integration**: Native Actions experience

### Migration Checklist

- [ ] Configure GitHub secrets (AWS roles)
- [ ] Update accounts.yml with your account details
- [ ] Test validation workflow with existing policies
- [ ] Run dry-run deployment to development account
- [ ] Gradually migrate accounts from Bitbucket to GitHub
- [ ] Update team documentation and runbooks