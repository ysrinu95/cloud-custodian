# Cloud Custodian Policies

This directory contains Cloud Custodian policies for AWS resource governance, security, and cost optimization.

## 🛡️ OIDC Authentication

All policies use OIDC authentication with the IAM role:
- **Role ARN**: `arn:aws:iam::172327596604:role/GitHubActions-CloudCustodian-Role`
- **Authentication**: GitHub Actions OIDC (no long-term credentials)
- **GitHub Secret**: `AWS_ROLE_ARN` (configured in repository settings)

## 📁 Policy Files

### 1. `example-policies.yml` - General Compliance
- **ec2-untagged-instances**: Find instances missing required tags
- **ebs-oversized-volumes**: Identify large unattached volumes
- **s3-unencrypted-buckets**: Ensure S3 encryption is enabled
- **security-groups-ssh-unrestricted**: Find unrestricted SSH access
- **elastic-ips-unused**: Identify unused Elastic IPs
- **rds-backup-disabled**: Check RDS backup configuration
- **lambda-public-access**: Find publicly accessible Lambda functions
- **ec2-stopped-instances-old**: Long-stopped EC2 instances
- **iam-users-old-access-keys**: Old IAM access keys

### 2. `security-policies.yml` - Security Focus
- **s3-public-buckets**: Critical - Public S3 buckets
- **security-groups-wide-open**: Wide-open security group rules
- **iam-admin-access-check**: Monitor admin-level permissions
- **nat-gateways-unused**: Unused NAT Gateways
- **cloudtrail-not-enabled**: CloudTrail configuration check

### 3. `cost-optimization-policies.yml` - Cost Management
- **ec2-low-utilization**: Low CPU utilization instances
- **ebs-unattached-volumes**: Unattached EBS volumes
- **ebs-old-snapshots**: Old EBS snapshots
- **rds-oversized-instances**: Oversized RDS instances
- **elb-no-targets**: Unused Classic Load Balancers
- **elbv2-no-targets**: Low-traffic Application Load Balancers
- **reserved-instances-unused**: Unused Reserved Instances
- **cloudwatch-large-log-groups**: Large CloudWatch log groups
- **lambda-unused-functions**: Unused Lambda functions

## 🚀 Running Policies

### Method 1: Manual Workflow Execution
1. Go to **Actions** → **"Cloud Custodian Operations"**
2. Click **"Run workflow"**
3. Choose action:
   - **validate**: Check policy syntax
   - **dryrun**: Show what would be affected (recommended)
   - **run**: Execute policies (makes actual changes)
4. Specify policy path (default: `policies/`)

### Method 2: Scheduled Execution
Policies run automatically daily at 6 AM UTC via the **"Scheduled Cloud Custodian Policies"** workflow:
- **Mode**: Dry run only (no changes made)
- **Coverage**: All policy categories
- **Artifacts**: Results uploaded for review

### Method 3: Specific Policy Categories
Use **"Scheduled Cloud Custodian Policies"** workflow manually:
- **security**: Security-focused policies only
- **cost-optimization**: Cost management policies only
- **compliance**: General compliance policies only
- **all**: All policy categories

## Policy Structure

Each policy follows this structure:

```yaml
policies:
  - name: policy-name
    description: What this policy does
    resource: aws.resource-type  # e.g., aws.ec2, aws.s3, aws.ebs
    filters:
      - # Conditions to match resources
    actions:
      - # Actions to take on matched resources
```

## Common Patterns

### Resource Filtering
- **Tag-based**: `"tag:TagName": present/absent/value`
- **State-based**: `"State.Name": running/stopped`
- **Value comparison**: `type: value, key: Size, op: gt, value: 100`

### Common Actions
- **Tag resources**: `type: tag, key: TagName, value: TagValue`
- **Mark for operation**: `type: mark-for-op, op: terminate/stop, days: 7`
- **Notifications**: `type: notify, transport: sns, to: [topic-arn]`

## Best Practices

1. **Always test with dry-run first**
2. **Start with tagging actions before destructive actions**
3. **Use descriptive names and descriptions**
4. **Include contact information in tags**
5. **Set up notifications for policy executions**

## Security Considerations

- Policies run with the permissions of the GitHub Actions role
- Review IAM permissions regularly
- Use least-privilege access
- Monitor policy executions via CloudTrail

## Adding New Policies

1. Create new `.yml` files in this directory
2. Follow the naming convention: `category-policies.yml`
3. Test locally first with dry-run
4. Use GitHub Actions for automated execution

## Resources

- [Cloud Custodian Documentation](https://cloudcustodian.io/)
- [Policy Examples](https://github.com/cloud-custodian/cloud-custodian/tree/main/docs/source/aws/examples)
- [AWS Resource Reference](https://cloudcustodian.io/docs/aws/resources/index.html)