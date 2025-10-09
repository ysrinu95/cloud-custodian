# Cloud Custodian Policies

This directory contains Cloud Custodian policy files for managing AWS resources.

## Policy Files

- **`example-policies.yml`** - Example policies for common use cases:
  - EC2 instances missing required tags
  - Oversized EBS volumes for cost optimization
  - S3 buckets without encryption

## Usage

### Via GitHub Actions (Recommended)

1. **Validate Policies**: 
   - Go to Actions → "Cloud Custodian Operations"
   - Select "validate" action
   - Run workflow

2. **Dry Run**: 
   - Go to Actions → "Cloud Custodian Operations"
   - Select "dryrun" action
   - Run workflow to see what would be affected

3. **Execute Policies**: 
   - Go to Actions → "Cloud Custodian Operations"
   - Select "run" action
   - Run workflow to execute policies

### Local Development

```bash
# Install Cloud Custodian
pip install c7n c7n-aws

# Validate policies
custodian validate policies/example-policies.yml

# Dry run
custodian run --dryrun -s output/ policies/example-policies.yml

# Execute (be careful!)
custodian run -s output/ policies/example-policies.yml
```

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