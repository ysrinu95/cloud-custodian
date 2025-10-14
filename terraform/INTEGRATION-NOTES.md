# Cloud Custodian Terraform Integration

This directory contains the integrated Terraform configuration that combines the best features from both the original `terraform/` and the enterprise `infrastructure/` configurations.

## Integration Summary

✅ **Successfully integrated and deduplicated:**
- **Provider configurations**: Combined GitHub OIDC setup with enterprise flexibility
- **Variable definitions**: Merged personal and enterprise variables with feature flags
- **IAM configurations**: Integrated Lambda execution roles with enterprise IAM setup
- **S3 resources**: Combined custodian outputs bucket with enterprise logging bucket
- **Output configurations**: Comprehensive outputs from both configurations
- **Enterprise features**: Added SQS mailer queue and SES configuration as optional features

## Key Features

### Core Infrastructure (Always Enabled)
- S3 bucket for Cloud Custodian outputs with versioning and encryption
- CloudWatch Log Group for centralized logging
- SNS Topic for basic notifications
- Lambda execution roles with appropriate permissions
- GitHub Actions OIDC integration for CI/CD

### Enterprise Features (Optional)
Enable with `enable_enterprise_features = true`:
- **Advanced Logging**: Separate S3 bucket for long-term log storage with lifecycle policies
- **SQS Mailer Queue**: For advanced notification processing
- **SES Email Identity**: For email notifications
- **Enhanced IAM**: Administrative access role for comprehensive policy execution

## Configuration Files

- `main.tf` - Primary infrastructure resources
- `variables.tf` - All configuration variables with defaults
- `outputs.tf` - Resource outputs for integration with other systems
- `mailer.tf` - Enterprise notification features
- `terraform.tfvars.example` - Example configuration file

## Usage

### Basic Setup (Personal/Small Team)
```hcl
# terraform.tfvars
aws_region = "us-east-1"
github_repository = "your-org/cloud-custodian"
environment = "dev"
project_name = "cloud-custodian"
enable_enterprise_features = false
```

### Enterprise Setup (Multi-Account/Advanced)
```hcl
# terraform.tfvars
aws_region = "us-east-1"
github_repository = "your-org/cloud-custodian"
environment = "production"
project_name = "cloud-custodian"
enable_enterprise_features = true
notification_email = "alerts@yourcompany.com"
```

## Deployment

1. Copy `terraform.tfvars.example` to `terraform.tfvars`
2. Customize the values for your environment
3. Run standard Terraform commands:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

## Migration Notes

- **Backup**: Original `terraform/` configuration backed up to `terraform-backup/`
- **Backward Compatibility**: Legacy Lambda execution role maintained for existing deployments
- **Feature Flags**: Enterprise features are opt-in via `enable_enterprise_features` variable
- **Multi-Environment**: Supports both simple single-account and complex multi-account deployments

## Removed Duplicates

The following duplicate configurations were consolidated:
- Provider configurations (AWS, random)
- Data sources (caller_identity, region)
- S3 bucket configurations (merged outputs + logs)
- IAM role definitions (consolidated execution roles)
- Output definitions (combined all outputs)

This integration provides a single, comprehensive Terraform configuration that scales from personal use to enterprise deployments while eliminating all duplication.