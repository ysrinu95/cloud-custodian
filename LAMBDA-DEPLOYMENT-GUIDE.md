# Cloud Custodian Deployment Modes Explained

## Current Setup: Infrastructure Only ✅

What we've deployed so far is the **base infrastructure**:
- 🔑 IAM roles for Lambda execution
- 📦 S3 bucket for policy outputs/logs
- 📊 CloudWatch log groups
- 📢 SNS topic for notifications

**No Lambda functions have been created yet** - this is expected!

## Cloud Custodian Execution Modes

### 1. **Pull Mode** (Current Workflow)
- ▶️ **How it works**: Policies run immediately when triggered
- 🕒 **When**: On-demand execution via GitHub Actions
- 💻 **Where**: Runs on GitHub Actions runners
- 🔄 **Persistence**: No persistent resources, runs and exits

```bash
# This is what the current workflow does:
custodian run -s output/ policies/example-policies.yml
```

### 2. **Lambda Mode** (Persistent Functions)
- ⚡ **How it works**: Creates dedicated Lambda functions for each policy
- 🕒 **When**: Triggered by CloudWatch Events, schedules, or other AWS events
- 💻 **Where**: Runs as AWS Lambda functions
- 🔄 **Persistence**: Lambda functions remain deployed and active

```bash
# This creates persistent Lambda functions:
custodian run --mode lambda --region us-east-1 policies/example-policies.yml
```

## Creating Persistent Lambda Functions

To deploy your policies as **persistent Lambda functions**, I'll create a new workflow:

### Option A: Lambda Mode Workflow (Serverless)
```yaml
# Deploy policies as Lambda functions
custodian run --mode lambda \
  --region us-east-1 \
  --role arn:aws:iam::ACCOUNT:role/CloudCustodian-Lambda-ExecutionRole \
  policies/
```

### Option B: Scheduled Mode Workflow (Event-driven)
```yaml
# Deploy policies with CloudWatch Events triggers
custodian run --mode cloudwatch \
  --region us-east-1 \
  --role arn:aws:iam::ACCOUNT:role/CloudCustodian-Lambda-ExecutionRole \
  policies/
```

## What You'll See After Lambda Deployment

Once you deploy in Lambda mode, you'll see:

### AWS Lambda Console:
- ✅ One Lambda function per policy (e.g., `custodian-ec2-untagged-instances`)
- ✅ Functions configured with proper IAM roles
- ✅ CloudWatch Events triggers (if scheduled)

### CloudWatch Console:
- ✅ Log groups for each Lambda function
- ✅ Metrics and monitoring
- ✅ Event rules and triggers

### Policy Execution:
- ✅ **Automatic execution** based on schedules or events
- ✅ **Persistent monitoring** - functions stay active
- ✅ **Event-driven responses** - react to AWS resource changes

## Cost Considerations

### Pull Mode (Current):
- 💰 **Cost**: Very low - only runs when triggered
- 📊 **Usage**: GitHub Actions minutes only

### Lambda Mode:
- 💰 **Cost**: AWS Lambda pricing + CloudWatch Events
- 📊 **Usage**: Continuous monitoring, per-execution billing
- 💡 **Estimate**: ~$1-10/month for typical policy sets

## Next Steps

Would you like me to:
1. **Create a Lambda deployment workflow** for persistent functions?
2. **Keep the current pull mode** for cost-effective on-demand execution?
3. **Create both options** so you can choose based on your needs?

Let me know your preference and I'll set up the appropriate deployment method!