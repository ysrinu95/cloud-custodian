# Real-Time Cloud Custodian Setup Guide

## 🚀 What You're Getting: Event-Driven Compliance

With this setup, you'll have **persistent Lambda functions** that respond to **real-time AWS events**:

### ⚡ Real-Time Event Triggers
- **EC2 Instance Launch** → Auto-tag untagged instances
- **S3 Bucket Creation** → Secure public buckets immediately  
- **Security Group Changes** → Block unrestricted SSH access
- **IAM Policy Creation** → Alert on overly permissive policies
- **RDS Instance Creation** → Flag publicly accessible databases

### 🕒 Scheduled Monitoring
- **Hourly EBS scans** → Find unencrypted volumes
- **Daily compliance reports** → Summary of violations
- **Weekly cost optimization** → Identify unused resources

## 📋 Deployment Steps

### 1. **Ensure Infrastructure is Ready**
First, make sure your base infrastructure is deployed:
- ✅ Run "Deploy Cloud Custodian Infrastructure" workflow if not done
- ✅ Verify Lambda execution role exists
- ✅ Confirm S3 bucket and SNS topic are created

### 2. **Deploy Lambda Functions**
1. Go to: **Actions** → **"Deploy Cloud Custodian Lambda Functions"**
2. Click **"Run workflow"**
3. Configure:
   - **deployment_action**: `deploy`
   - **policy_path**: `policies` (or specify custom path)
   - **lambda_timeout**: `300` (5 minutes)
   - **lambda_memory**: `512` (MB)
4. Click **"Run workflow"**

### 3. **What Gets Created**

#### Lambda Functions (One per policy):
```
custodian-ec2-untagged-instances-realtime
custodian-s3-public-bucket-remediation-realtime  
custodian-security-group-ssh-remediation-realtime
custodian-iam-policy-monitoring-realtime
custodian-ebs-unencrypted-volumes-scheduled
custodian-rds-public-access-remediation-realtime
```

#### CloudWatch Event Rules:
```
custodian-ec2-untagged-instances-realtime  (CloudTrail: RunInstances)
custodian-s3-public-bucket-remediation-realtime  (CloudTrail: CreateBucket)
custodian-security-group-ssh-remediation-realtime  (CloudTrail: AuthorizeSecurityGroupIngress)
custodian-iam-policy-monitoring-realtime  (CloudTrail: CreatePolicy)
custodian-ebs-unencrypted-volumes-scheduled  (Schedule: rate(1 hour))
custodian-rds-public-access-remediation-realtime  (CloudTrail: CreateDBInstance)
```

#### CloudWatch Log Groups:
```
/aws/lambda/custodian-ec2-untagged-instances-realtime
/aws/lambda/custodian-s3-public-bucket-remediation-realtime
... (one per function)
```

## 🔧 How Real-Time Monitoring Works

### Event Flow:
1. **AWS Resource Created/Modified** (e.g., EC2 instance launched)
2. **CloudTrail captures the event** 
3. **CloudWatch Event Rule triggers** the corresponding Lambda
4. **Lambda function executes** Cloud Custodian policy
5. **Automatic remediation** applied (tagging, securing, etc.)
6. **SNS notification sent** to relevant teams
7. **Results logged** to CloudWatch Logs

### Example: EC2 Instance Launch
```
1. User launches EC2 instance without tags
2. CloudTrail logs "RunInstances" event  
3. CloudWatch Event Rule triggers custodian-ec2-untagged-instances-realtime
4. Lambda function tags the instance with "AutoTagged: true"
5. SNS notification sent about auto-tagging
6. Compliance achieved in < 30 seconds
```

## 📊 Monitoring Your Functions

### AWS Console Locations:
- **Lambda Functions**: [AWS Lambda Console](https://console.aws.amazon.com/lambda/home?region=us-east-1#/functions)
- **Event Rules**: [CloudWatch Events Console](https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#rules:)
- **Logs**: [CloudWatch Logs Console](https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#logsV2:log-groups)
- **SNS Topics**: [SNS Console](https://console.aws.amazon.com/sns/v3/home?region=us-east-1#/topics)

### Key Metrics to Watch:
- **Lambda Invocations** → How often policies trigger
- **Lambda Errors** → Any policy execution failures  
- **Lambda Duration** → Policy execution time
- **SNS Messages** → Compliance notifications sent

## 💰 Cost Considerations

### Typical Monthly Costs:
- **Lambda Executions**: $1-5 (depends on event frequency)
- **CloudWatch Events**: $1-2 (rule evaluations)
- **CloudWatch Logs**: $2-5 (log storage)
- **SNS Messages**: <$1 (notifications)
- **Total Estimated**: $5-15/month for active monitoring

### Cost Optimization:
- ✅ Functions only run when triggered (no idle costs)
- ✅ Efficient memory allocation (512MB default)
- ✅ Reasonable timeouts (5 minutes default)
- ✅ Log retention policies prevent excessive storage

## 🛠️ Customization Options

### Adding New Policies:
1. Create new policy files in `policies/` directory
2. Define event triggers (`cloudtrail` or `periodic`)
3. Re-run the deployment workflow
4. New Lambda functions will be created automatically

### Modifying Existing Policies:
1. Update policy files in repository
2. Run deployment workflow with `update` action
3. Lambda functions will be updated with new configurations

### Removing All Functions:
1. Run deployment workflow with `remove` action
2. All Lambda functions and Event Rules will be deleted

## 🎯 Next Steps

After deployment, you'll have:
- ✅ **24/7 real-time compliance monitoring**
- ✅ **Automatic remediation** of common issues
- ✅ **Instant notifications** for security violations
- ✅ **Detailed audit trail** in CloudWatch Logs
- ✅ **Scalable architecture** for additional policies

Your AWS environment will be continuously monitored and automatically remediated! 🚀