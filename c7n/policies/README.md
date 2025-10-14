# Cloud Custodian Policies

This directory contains Cloud Custodian policies for AWS resource governance, security, and cost optimization.

## 📁 Policy Categories

### Enterprise Policies (from bundle)
- `account.yml` - Account-level monitoring and compliance
- `cloudwatch.yml` - CloudWatch monitoring and alerting policies
- `ec2.yml` - EC2 instance governance and security
- `ecs.yml` - ECS service monitoring and optimization
- `guardduty.yml` - GuardDuty finding management
- `iam.yml` - IAM security and compliance
- `lambda.yml` - Lambda function governance
- `lb.yml` - Load balancer optimization
- `rds.yml` - RDS database security and cost management
- `s3.yml` - S3 bucket security and compliance
- `schedule.yml` - Scheduled resource management
- `securityhub.yml` - Security Hub finding management
- `tagging.yml` - Resource tagging compliance
- `_baseline.yml` - Baseline configuration and shared variables

### User Policies (integrated from original policies/)
- `user-compliance.yml` - General compliance and governance policies
- `user-security.yml` - Security-focused monitoring and remediation
- `user-cost-optimization.yml` - Cost management and optimization
- `user-realtime.yml` - Real-time event-driven policies

## 🔧 Policy Configuration

### Enterprise Features
The enterprise policies include advanced features:
- **Multi-account support** with workspace-based role assumption
- **SQS-based notifications** for centralized processing
- **Slack integration** with formatted messages
- **Email notifications** with HTML templates
- **CloudTrail event triggers** for real-time responses
- **Comprehensive tagging** and metadata

### User Policies
The user policies provide:
- **GitHub OIDC authentication** for CI/CD integration
- **SNS notifications** for basic alerting
- **Flexible filtering** and action configurations
- **Cost optimization** focus with practical remediation
- **Security compliance** with best practices

## 🚀 Deployment

### Using c7n/scripts
The policies can be deployed using the included scripts:

```bash
# Deploy all policies
./c7n/scripts/deploy-policies.sh

# Deploy only updated policies
./c7n/scripts/deploy-updated-policies.sh

# Deploy mailer for notifications
./c7n/scripts/deploy-mailer.sh

# Clean up removed policies
./c7n/scripts/clean-removed-policies.sh
```

### Using GitHub Actions
Workflows are configured to use c7n/scripts and c7n/policies:
- **Scheduled execution** via `scheduled-custodian.yml`
- **Manual execution** via `cloud-custodian.yml`
- **Lambda deployment** via `deploy-lambda.yml`

## 📋 Policy Structure

### Enterprise Policy Format
```yaml
vars:
  tags: &tags
    contact: devops@company.com
    environment: "{environment}"
    repo: devops/cloud-custodian/c7n
  slack-notify: &slack-notify
    slack_template: slack_default
    to:
      - https://hooks.slack.com/services/...
    transport:
      type: sqs
      queue: https://sqs.region.amazonaws.com/account/queue

policies:
  - name: policy-name
    resource: aws.resource-type
    description: Policy description
    mode:
      type: periodic|cloudtrail
      schedule: cron(...)
      role: arn:aws:iam::{account_id}:role/path/role-name
      tags: *tags
    filters:
      - # filtering conditions
    actions:
      - # actions to take
```

### User Policy Format
```yaml
policies:
  - name: policy-name
    description: Policy description
    resource: aws.resource-type
    filters:
      - # filtering conditions
    actions:
      - # actions to take
```

## 🔄 Migration Notes

- **Backup**: Original `policies/` directory backed up to `policies-backup/`
- **Integration**: User policies renamed with `user-` prefix for clarity
- **Compatibility**: Both enterprise and user policy formats supported
- **Scripts**: Updated to use `c7n/scripts/` for deployment
- **Workflows**: Modified to reference `c7n/policies/` as the primary location

## 🛠️ Configuration

### Environment Variables
Set in your deployment environment:
- `CUSTODIAN_ROLE` - IAM role for policy execution
- `NOTIFICATION_QUEUE` - SQS queue for notifications (enterprise)
- `SLACK_WEBHOOK` - Slack webhook URL (enterprise)

### Authentication
- **Enterprise**: Uses role assumption per account/environment
- **User**: Uses GitHub OIDC for CI/CD authentication

## 📚 Resources

- [Cloud Custodian Documentation](https://cloudcustodian.io/)
- [Policy Examples](https://github.com/cloud-custodian/cloud-custodian/tree/main/docs/source/aws/examples)
- [AWS Resource Reference](https://cloudcustodian.io/docs/aws/resources/index.html)