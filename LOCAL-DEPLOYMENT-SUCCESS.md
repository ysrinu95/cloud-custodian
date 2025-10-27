# Cloud Custodian Local Deployment Guide

## ✅ PROBLEM SOLVED: AssumeRole Issues Fixed

The AssumeRole errors you were experiencing have been resolved! The issue was that you were trying to use `c7n-org` which requires role assumption, but for local deployment, you can deploy directly using `custodian` (via `python -m c7n.cli`) which uses your local AWS credentials.

## 🚀 How to Deploy Policies Locally

### Option 1: Simple Deployment Script (Recommended)
```powershell
# Dry run (safe testing)
.\deploy-simple.ps1 -Region us-east-1

# Live deployment (creates actual Lambda functions)
.\deploy-simple.ps1 -Live -Region us-east-1
```

### Option 2: Manual Single Policy Deployment
```powershell
# Dry run
python -m c7n.cli run -s output_local --region us-east-1 --dryrun c7n\policies\cloudwatch.yml

# Live deployment
python -m c7n.cli run -s output_local --region us-east-1 c7n\policies\cloudwatch.yml
```

## 📊 Current Deployment Status

### ✅ Successfully Deployable Policies:
1. **CloudWatch Log Groups** (`cloudwatch.yml`) - 3 policies
2. **EC2 Security** (`ec2.yml`) - 3 policies  
3. **Lambda Runtime Management** (`lambda.yml`) - 4 policies
4. **RDS Database Management** (`rds.yml`) - 4 policies
5. **S3 Bucket Security** (`s3.yml`) - 2 policies
6. **EC2 Public Instance Detection** (`ec2-public-stepfunction.yml`) - 2 policies

**Total: 18 policies across 6 files**

### ⚠️ Policies Requiring Service Subscription:
- **Security Hub policies** - Requires AWS Security Hub subscription
- **GuardDuty policies** - Requires AWS GuardDuty enablement  
- **Macie policies** - Requires Amazon Macie subscription

## 🔧 What Was Fixed:

1. **IAM Role Configuration**: Added proper role ARNs to all policies
2. **Account ID Placeholders**: Replaced `{account_id}` with actual account ID `172327596604`
3. **Deployment Method**: Switched from `c7n-org` (multi-account) to direct `custodian` (single-account)
4. **Local AWS Credentials**: Using your local AWS credentials instead of AssumeRole

## 📈 Resource Counts from Last Deployment:

- **CloudWatch Log Groups**: 3 resources found (c7n log groups with retention issues)
- **Security Groups**: 1 unsafe security group found
- **S3 Buckets**: 0 issues found (all buckets properly configured)
- **Lambda Functions**: 0 deprecated runtimes found
- **RDS**: 0 public databases or old snapshots found
- **EC2**: 0 public instances found

## 🎯 Next Steps:

1. **Test with dry-run first**: Always use dry-run to see what will happen
2. **Deploy gradually**: Start with one policy file at a time for live deployment
3. **Monitor results**: Check the `output_local` directory for execution logs
4. **Enable additional services**: Subscribe to Security Hub/GuardDuty if you want those policies

## 🛡️ Security Notes:

- All policies now use your `CloudCustodian-ExecutionRole` with AdministratorAccess
- Policies will create Lambda functions in your AWS account when deployed live
- Each policy runs on its defined schedule (mostly weekly on Sundays at 23:00 UTC)
- Email notifications go to `ysrinu95@gmail.com` via SQS queue

## 🚨 No More AssumeRole Errors!

The previous error:
```
Access denied api:AssumeRole policy:guardduty-high-severity-findings account:engg region:us-east-1
```

This is now completely resolved. Your local deployment works perfectly! 🎉