# Security Findings Policies Testing Guide

This directory contains comprehensive testing tools for the Cloud Custodian security findings policies defined in `security-findings.yml`.

## 📋 Available Security Policies

### Real-time CloudTrail-triggered Policies:

1. **🛡️ GuardDuty High Severity Findings** (`guardduty-high-severity-findings`)
   - **Triggers**: GuardDuty CreateFinding events (severity ≥ 7.0)
   - **Actions**: Finding tagging, high-priority notifications
   - **Test**: Simulates SSH brute force attack detection

2. **📋 Config Compliance Violations** (`config-compliance-violations`)
   - **Triggers**: AWS Config PutEvaluations (NON_COMPLIANT)
   - **Actions**: Resource tagging via Lambda, compliance notifications
   - **Test**: Creates public S3 bucket violating access rules

3. **🔒 Security Hub Critical Findings** (`securityhub-critical-findings`)
   - **Triggers**: Security Hub BatchImportFindings (HIGH/CRITICAL)
   - **Actions**: Workflow status updates, security team alerts
   - **Test**: Creates CRITICAL finding for unencrypted S3 bucket

4. **🔍 Macie Sensitive Data Discovery** (`macie-sensitive-data-findings`)
   - **Triggers**: Macie ClassificationResult events (severity ≥ 7)
   - **Actions**: Immediate bucket protection (encryption, versioning, public block)
   - **Test**: Creates bucket with fake PII data

5. **🔐 IAM Access Analyzer External Access** (`iam-access-analyzer-external-access`)
   - **Triggers**: Access Analyzer CreateFinding events
   - **Actions**: Finding archival, IAM team notifications
   - **Test**: Creates IAM role with external account trust

6. **📊 S3 Access Logs Suspicious Activity** (`s3-access-logs-suspicious-activity`)
   - **Triggers**: S3 GetObject/DeleteObject/PutBucketPolicy events
   - **Actions**: Bucket tagging, versioning, security alerts
   - **Test**: Accesses files with suspicious names (passwords, secrets)

7. **⚠️ CloudTrail High-Risk Security Events** (`cloudtrail-security-events`)
   - **Triggers**: IAM, security service, and root account events
   - **Actions**: Critical security alerts
   - **Test**: Simulates root login failure and IAM policy changes

### Periodic Policy:

8. **📈 Security Findings Daily Summary** (`security-findings-daily-summary`)
   - **Schedule**: Weekly (Sunday 23:00 UTC)
   - **Actions**: Aggregated security report via Lambda
   - **Test**: Manual aggregator invocation

## 🚀 How to Test Policies

### Option 1: Jenkins Pipeline (Recommended)

Use the updated `cloud-custodian-demo.groovy` Jenkins pipeline:

```groovy
// New security findings test options available:
'🛡️ GuardDuty: High Severity Findings Detection'
'📋 Config: Compliance Violations Response'
'🔒 Security Hub: Critical Findings Response'
'🔍 Macie: Sensitive Data Discovery'
'🔐 IAM Access Analyzer: External Access Detection'
'📊 S3 Access Logs: Suspicious Activity Detection'
'⚠️ CloudTrail: High-Risk Security Events'
'📈 Security Findings: Daily Summary Report'
'🌈 Security: Run All Security Findings Tests'
```

### Option 2: Direct Script Execution

```bash
# Make script executable
chmod +x c7n/scripts/test-security-findings.sh

# Interactive menu
./c7n/scripts/test-security-findings.sh

# Command line options
./c7n/scripts/test-security-findings.sh guardduty
./c7n/scripts/test-security-findings.sh config
./c7n/scripts/test-security-findings.sh securityhub
./c7n/scripts/test-security-findings.sh macie
./c7n/scripts/test-security-findings.sh accessanalyzer
./c7n/scripts/test-security-findings.sh s3logs
./c7n/scripts/test-security-findings.sh cloudtrail
./c7n/scripts/test-security-findings.sh summary
./c7n/scripts/test-security-findings.sh all
./c7n/scripts/test-security-findings.sh cleanup
```

## 🔄 Testing Process

Each test follows this pattern:

1. **Resource Creation**: Creates AWS resources that will trigger the policy
2. **Event Simulation**: Sends CloudWatch Events to trigger Lambda functions
3. **Wait Period**: Allows time for asynchronous processing (15-20 seconds)
4. **Verification**: Checks Lambda logs and resource changes
5. **Cleanup**: Removes test resources automatically

## 📊 Expected Results

### Successful Test Indicators:

- ✅ Lambda function logs show policy execution
- ✅ CloudWatch Events successfully delivered
- ✅ SQS messages queued for email notifications
- ✅ Resource modifications applied (tagging, encryption, etc.)
- ✅ No errors in Lambda execution

### Notification Channels:

- **Email**: Queued via SQS to `custodian-mailer-queue`
- **Slack**: Direct webhook notifications (if configured)
- **Teams**: Security and compliance teams notified

## 🧹 Cleanup

The test script automatically cleans up resources, but you can run manual cleanup:

```bash
./c7n/scripts/test-security-findings.sh cleanup
```

This removes:
- Test S3 buckets (custodian-test-*, custodian-macie-*, custodian-s3-logs-*)
- Test IAM users (custodian-test-user-*)
- Test IAM roles (CustodianTestRole-*)
- Temporary files

## 🔍 Monitoring Test Results

### Lambda Logs:
```bash
# View specific policy logs
aws logs tail /aws/lambda/custodian-guardduty-high-severity-findings --since 5m
aws logs tail /aws/lambda/custodian-config-compliance-violations --since 5m
aws logs tail /aws/lambda/custodian-securityhub-critical-findings --since 5m
```

### SQS Queue Status:
```bash
# Check mailer queue
aws sqs get-queue-attributes \
  --queue-url https://sqs.us-east-1.amazonaws.com/757541135089/custodian-mailer-queue \
  --attribute-names ApproximateNumberOfMessages
```

### Email Monitoring:
Use the mailer monitoring script:
```bash
./c7n/scripts/monitor-mailer-simple.sh
```

## ⚡ Real-time vs. Simulated Testing

### Real-time Policies:
These policies are **always active** and respond to actual AWS API calls:
- Creating actual resources triggers the policies immediately
- CloudTrail events are processed within 5-15 seconds
- No manual policy execution needed

### Test Simulation:
- We create real AWS resources (S3 buckets, IAM users, etc.)
- We send CloudWatch Events to trigger Lambda functions
- This mimics the real CloudTrail event flow
- Cleanup removes test resources automatically

## 🔧 Troubleshooting

### Common Issues:

1. **Lambda Not Found**:
   ```bash
   # Check if Lambda functions are deployed
   aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `custodian-`)].FunctionName'
   ```

2. **No CloudWatch Events**:
   ```bash
   # Check CloudWatch Events rules
   aws events list-rules --name-prefix custodian
   ```

3. **SQS Queue Issues**:
   ```bash
   # Verify mailer queue exists
   aws sqs get-queue-url --queue-name custodian-mailer-queue
   ```

4. **Permission Errors**:
   ```bash
   # Check Cloud Custodian execution role
   aws iam get-role --role-name cloud-custodian
   ```

### Debug Mode:

Set environment variables for detailed logging:
```bash
export AWS_REGION=us-east-1
export C7N_DEBUG=true
./c7n/scripts/test-security-findings.sh
```

## 📈 Performance Metrics

### Expected Response Times:
- **GuardDuty**: 5-10 seconds
- **Config**: 15-30 seconds (simulated, real takes 5-15 minutes)
- **Security Hub**: 10-20 seconds
- **Macie**: 15-25 seconds
- **Access Analyzer**: 10-15 seconds
- **S3 Access Logs**: 15-20 seconds
- **CloudTrail Events**: 5-15 seconds
- **Daily Summary**: 20-30 seconds

### Full Test Suite: ~20-25 minutes

## 🎯 Production Considerations

### Before Production Deployment:
1. Update SQS queue URLs in policies
2. Configure Slack webhook URLs
3. Update email recipient lists
4. Test notification delivery end-to-end
5. Verify IAM permissions for all services
6. Enable AWS services (GuardDuty, Security Hub, Macie, Config, Access Analyzer)

### Monitoring in Production:
1. Set up CloudWatch dashboards
2. Configure Lambda error alerts
3. Monitor SQS queue depth
4. Track policy execution metrics
5. Regular testing with non-production accounts

---

For questions or issues, contact: srinivasula.yallala@optum.com