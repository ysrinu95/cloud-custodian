# Cloud Custodian Demo Resource Cleanup Guide

## 🚨 Resource Cleanup Problem

When running Cloud Custodian security findings tests, resources are created in AWS that may fail to cleanup automatically due to:

- Lambda timeouts during cleanup
- IAM permission issues  
- Resource dependencies
- Network connectivity issues
- AWS API rate limiting
- Concurrent resource modifications

## 🧹 Cleanup Options Available

### 1. **Security Test Resources Only** (`🧹 Cleanup: Security Test Resources Only`)

**What it cleans:**
- S3 buckets: `custodian-test-*`, `custodian-macie-*`, `custodian-s3-logs-*`
- IAM users: `custodian-test-user-*`
- IAM roles: `CustodianTestRole-*`
- Test Security Hub findings with `[TEST]` or `[DEMO]` prefix
- Temporary files from security tests

**When to use:**
- After running security findings tests
- When you only want to clean security test resources
- When original EC2/RDS/EBS demo resources should be preserved

**How to run:**
```bash
# Jenkins Pipeline
Select: "🧹 Cleanup: Security Test Resources Only"

# Command Line
./c7n/scripts/test-security-findings.sh cleanup
```

### 2. **Comprehensive Cleanup** (`🗑️ Cleanup: All Demo Resources (Comprehensive)`)

**What it cleans:**
- **ALL S3 buckets** with `custodian`, `test`, or `demo` in name
- **ALL EC2 instances** with `TestResource` tag or demo names
- **ALL EBS volumes** with `TestResource` tag
- **ALL EBS snapshots** with `TestResource` tag or demo descriptions
- **ALL IAM users** starting with `custodian-test-`, `test-`, `demo-`
- **ALL IAM roles** starting with `CustodianTestRole-`, `custodian-test-`, `test-`, `demo-`
- **ALL test RDS instances** starting with `custodian-test-`
- **ALL test Security Hub findings**
- **ALL temporary files**

**When to use:**
- When you want to completely clean the account of all demo resources
- Before important testing or production activities
- When experiencing unexpected AWS charges from test resources
- When resources failed to cleanup from multiple test runs

**⚠️ WARNING:**
This will remove ALL demo and test resources, including from original EC2/RDS/EBS demos!

**How to run:**
```bash
# Jenkins Pipeline
Select: "🗑️ Cleanup: All Demo Resources (Comprehensive)"

# Command Line  
./c7n/scripts/test-security-findings.sh force-cleanup
# (Requires typing "DELETE-ALL" to confirm)
```

### 3. **Scan and Report Only** (`🔍 Cleanup: Scan and Report Resources Only`)

**What it does:**
- **Read-only scan** of all demo and test resources
- Detailed inventory with resource counts and billing impact
- Cost estimation for billable resources
- Recommendations for cleanup actions
- No resources are modified or deleted

**When to use:**
- Before deciding which cleanup option to use
- To assess potential AWS costs from test resources
- For auditing and inventory purposes
- To verify cleanup completion

**How to run:**
```bash
# Jenkins Pipeline
Select: "🔍 Cleanup: Scan and Report Resources Only"

# Command Line
./c7n/scripts/test-security-findings.sh scan
```

## 📊 Typical Resource Cleanup Scenarios

### Scenario 1: Security Test Failed Cleanup
```
Problem: Ran GuardDuty test, S3 bucket cleanup failed
Resources: custodian-test-bucket-123456, test IAM user, temp files

Solution: 
✅ Use "Security Test Resources Only" cleanup
⏱️ Time: 2-3 minutes
💰 Cost Impact: Low
```

### Scenario 2: Multiple Failed Test Runs
```
Problem: Ran several security tests, multiple resources remain
Resources: 5 S3 buckets, 3 IAM users, 2 IAM roles, Security Hub findings

Solution:
✅ Use "Security Test Resources Only" cleanup
⏱️ Time: 3-5 minutes  
💰 Cost Impact: Medium
```

### Scenario 3: Complete Demo Environment Cleanup
```
Problem: Account has resources from all demos over several weeks
Resources: 10+ S3 buckets, EC2 instances, EBS volumes, RDS, IAM resources

Solution:
✅ Use "Comprehensive Cleanup" (after scanning)
⏱️ Time: 5-10 minutes
💰 Cost Impact: High (removes all billable resources)
```

### Scenario 4: Audit Before Production
```
Problem: Need to verify no test resources before prod deployment
Resources: Unknown quantity and type

Solution:
✅ Use "Scan and Report" first, then appropriate cleanup
⏱️ Time: 1-2 minutes for scan
💰 Cost Impact: Assessment only
```

## 🛠️ Cleanup Process Details

### Security Test Resources Cleanup Process:
1. **S3 Buckets**: Remove all objects, disable versioning, delete bucket
2. **IAM Users**: Remove policies, access keys, group memberships, delete user  
3. **IAM Roles**: Detach policies, remove inline policies, remove instance profiles, delete role
4. **Security Hub**: Archive test findings with RESOLVED status
5. **Temp Files**: Remove all test-related temporary files

### Comprehensive Cleanup Process:
1. **Aggressive S3 Cleanup**: Force remove all versions, delete markers, objects
2. **EC2 Termination**: Terminate instances, wait for termination completion
3. **EBS Cleanup**: Delete volumes after instance termination, delete snapshots
4. **IAM Purge**: Remove all test users/roles with all associated resources
5. **RDS Cleanup**: Delete with skip-final-snapshot and delete-automated-backups
6. **Security Hub**: Archive all test findings
7. **File Cleanup**: Remove all demo-related temporary files

### Scan Process:
1. **Inventory Collection**: Query all AWS services for demo/test resources
2. **Cost Assessment**: Identify billable vs non-billable resources
3. **Detailed Reporting**: Show resource counts, types, and status
4. **Recommendations**: Suggest appropriate cleanup actions

## ⚡ Quick Reference Commands

```bash
# Interactive menu with all options
./c7n/scripts/test-security-findings.sh

# Quick scan to see what exists
./c7n/scripts/test-security-findings.sh scan

# Clean only security test resources
./c7n/scripts/test-security-findings.sh cleanup

# Nuclear option - clean everything (requires confirmation)
./c7n/scripts/test-security-findings.sh force-cleanup

# Run specific security test
./c7n/scripts/test-security-findings.sh guardduty

# Validate Lambda deployment before testing
./c7n/scripts/validate-security-deployment.sh
```

## 🔍 Verification Commands

After cleanup, verify results:

```bash
# Check S3 buckets
aws s3 ls | grep -E "(custodian|test|demo)"

# Check EC2 instances  
aws ec2 describe-instances --filters "Name=tag:TestResource,Values=true" --query 'Reservations[].Instances[].InstanceId'

# Check IAM users
aws iam list-users --query 'Users[?starts_with(UserName, `custodian-test`)].UserName'

# Check IAM roles
aws iam list-roles --query 'Roles[?starts_with(RoleName, `CustodianTestRole`)].RoleName'

# Or use the scan function
./c7n/scripts/test-security-findings.sh scan
```

## 💰 Cost Impact Analysis

### Billable Resources:
- **Running EC2 instances**: $0.0116/hour (t3.micro)
- **Available EBS volumes**: $0.10/GB/month
- **EBS snapshots**: $0.05/GB/month  
- **S3 storage**: $0.023/GB/month
- **Running RDS instances**: $0.017/hour (db.t3.micro)

### Non-billable Resources:
- IAM users and roles (no cost)
- Security Hub findings (no additional cost)
- Temporary files (no cost)

### Example Cost Scenarios:
```
Light Testing: 1 S3 bucket + 1 IAM user = ~$0.50/month
Medium Testing: 3 S3 buckets + 1 EC2 + 1 EBS = ~$15/month  
Heavy Testing: 5 S3 buckets + 3 EC2 + 5 EBS + RDS = ~$50/month
```

## 🚨 Emergency Cleanup

If resources are causing unexpected charges:

```bash
# 1. Immediate scan
./c7n/scripts/test-security-findings.sh scan

# 2. Stop all billable resources immediately
aws ec2 describe-instances --filters "Name=tag:TestResource,Values=true" "Name=instance-state-name,Values=running" --query 'Reservations[].Instances[].InstanceId' --output text | xargs -r aws ec2 stop-instances --instance-ids

# 3. Delete RDS instances (no final snapshot)
aws rds describe-db-instances --query 'DBInstances[?starts_with(DBInstanceIdentifier, `custodian-test`)].DBInstanceIdentifier' --output text | xargs -r -I {} aws rds delete-db-instance --db-instance-identifier {} --skip-final-snapshot --delete-automated-backups

# 4. Run comprehensive cleanup
./c7n/scripts/test-security-findings.sh force-cleanup
```

## 📞 Support

For issues with resource cleanup:

1. **First**: Run scan to identify remaining resources
2. **Check**: AWS CloudTrail for any error events during cleanup
3. **Verify**: IAM permissions for the cleanup operations
4. **Manual**: Use AWS Console to manually remove stubborn resources
5. **Contact**: srinivasula.yallala@optum.com for assistance

---

**Remember**: Always run a scan before and after cleanup to verify the process worked correctly!