#!/bin/bash
# Master Test Script for Security Findings Policies
# Tests all policies in security-findings.yml

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="${AWS_REGION:-us-east-1}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_test() {
    echo -e "${PURPLE}🧪 $1${NC}"
}

# Main menu function
show_menu() {
    echo "════════════════════════════════════════════════════════════"
    echo "🛡️  Cloud Custodian Security Findings Test Suite"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "Available Tests:"
    echo "  1) 🛡️  GuardDuty High Severity Findings"
    echo "  2) 📋 Config Compliance Violations"
    echo "  3) 🔒 Security Hub Critical Findings"
    echo "  4) 🔍 Macie Sensitive Data Discovery"
    echo "  5) 🔐 IAM Access Analyzer External Access"
    echo "  6) 📊 S3 Access Logs Suspicious Activity"
    echo "  7) ⚠️  CloudTrail High-Risk Security Events"
    echo "  8) 📈 Security Findings Daily Summary"
    echo "  9) 🌈 Run All Tests (20+ minutes)"
    echo " 10) 🧹 Cleanup Test Resources (Security Tests Only)"
    echo " 11) 🗑️ Force Cleanup All Resources (Comprehensive)"
    echo " 12) 🔍 Scan and Report Resources Only"
    echo "  q) Quit"
    echo ""
}

# Test functions
test_guardduty_findings() {
    log_test "Testing GuardDuty High Severity Findings Policy"
    echo "Policy: guardduty-high-severity-findings"
    echo "Lambda: custodian-guardduty-high-severity-findings"
    echo ""
    
    # Create simulated GuardDuty finding
    FINDING_ID="test-finding-$(date +%s)"
    
    log_info "Creating test GuardDuty finding..."
    
    # Generate test event
    cat > /tmp/guardduty-test-event.json << EOF
{
  "version": "0",
  "id": "$(uuidgen)",
  "detail-type": "GuardDuty Finding",
  "source": "aws.guardduty",
  "account": "$(aws sts get-caller-identity --query Account --output text)",
  "time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "region": "${REGION}",
  "detail": {
    "schemaVersion": "2.0",
    "accountId": "$(aws sts get-caller-identity --query Account --output text)",
    "region": "${REGION}",
    "partition": "aws",
    "id": "${FINDING_ID}",
    "arn": "arn:aws:guardduty:${REGION}:$(aws sts get-caller-identity --query Account --output text):detector/test/finding/${FINDING_ID}",
    "type": "UnauthorizedAccess:EC2/SSHBruteForce",
    "resource": {
      "resourceType": "Instance",
      "instanceDetails": {
        "instanceId": "i-test$(date +%s)",
        "instanceType": "t2.micro"
      }
    },
    "severity": 8.5,
    "title": "[TEST] SSH brute force attack detected",
    "description": "Test GuardDuty finding for Cloud Custodian policy verification"
  }
}
EOF

    # Send event to CloudWatch Events
    aws events put-events \
        --entries file:///tmp/guardduty-test-event.json \
        --region ${REGION}
    
    log_success "Test GuardDuty finding created: ${FINDING_ID}"
    
    # Wait and check logs
    log_info "Waiting 15 seconds for Lambda to process..."
    sleep 15
    
    # Check Lambda logs
    log_info "Checking Lambda execution logs..."
    aws logs tail /aws/lambda/custodian-guardduty-high-severity-findings \
        --since 2m \
        --region ${REGION} \
        --format short || log_warning "No recent logs found"
    
    rm -f /tmp/guardduty-test-event.json
    log_success "GuardDuty test completed"
}

test_config_compliance() {
    log_test "Testing Config Compliance Violations Policy"
    echo "Policy: config-compliance-violations"
    echo "Lambda: custodian-config-compliance-violations"
    echo ""
    
    # Create S3 bucket that violates public access rules
    BUCKET_NAME="custodian-test-config-$(date +%s)"
    
    log_info "Creating test S3 bucket with public access..."
    aws s3 mb s3://${BUCKET_NAME} --region ${REGION}
    
    # Make bucket public (violates s3-bucket-public-read-prohibited)
    aws s3api put-bucket-acl \
        --bucket ${BUCKET_NAME} \
        --acl public-read \
        --region ${REGION}
    
    log_success "Created public bucket: ${BUCKET_NAME}"
    
    # Simulate Config evaluation event
    cat > /tmp/config-test-event.json << EOF
{
  "version": "0",
  "id": "$(uuidgen)",
  "detail-type": "Config Rules Evaluation Result",
  "source": "aws.config",
  "account": "$(aws sts get-caller-identity --query Account --output text)",
  "time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "region": "${REGION}",
  "detail": {
    "requestParameters": {
      "evaluations": [{
        "complianceResourceId": "${BUCKET_NAME}",
        "complianceResourceType": "AWS::S3::Bucket"
      }]
    },
    "configRuleName": "s3-bucket-public-read-prohibited",
    "compliance": {
      "ComplianceType": "NON_COMPLIANT"
    }
  }
}
EOF

    aws events put-events \
        --entries file:///tmp/config-test-event.json \
        --region ${REGION}
    
    log_info "Waiting 20 seconds for Lambda to process..."
    sleep 20
    
    # Check Lambda logs
    log_info "Checking Lambda execution logs..."
    aws logs tail /aws/lambda/custodian-config-compliance-violations \
        --since 2m \
        --region ${REGION} \
        --format short || log_warning "No recent logs found"
    
    # Cleanup
    log_info "Cleaning up test bucket..."
    aws s3 rb s3://${BUCKET_NAME} --force --region ${REGION} || true
    rm -f /tmp/config-test-event.json
    
    log_success "Config compliance test completed"
}

test_securityhub_findings() {
    log_test "Testing Security Hub Critical Findings Policy"
    echo "Policy: securityhub-critical-findings"
    echo "Lambda: custodian-securityhub-critical-findings"
    echo ""
    
    FINDING_ID="securityhub-test-$(date +%s)"
    
    log_info "Creating test Security Hub finding..."
    
    # Create test Security Hub finding
    cat > /tmp/securityhub-finding.json << EOF
{
  "SchemaVersion": "2018-10-08",
  "Id": "${FINDING_ID}",
  "ProductArn": "arn:aws:securityhub:${REGION}:$(aws sts get-caller-identity --query Account --output text):product/aws/securityhub",
  "GeneratorId": "aws-foundational-security-best-practices/v/1.0.0/S3.4",
  "AwsAccountId": "$(aws sts get-caller-identity --query Account --output text)",
  "Types": ["Software and Configuration Checks/AWS Security Best Practices"],
  "Title": "[TEST] S3 bucket should have server-side encryption enabled",
  "Description": "Test Security Hub finding for Cloud Custodian policy verification",
  "Severity": {
    "Label": "CRITICAL",
    "Normalized": 90
  },
  "RecordState": "ACTIVE",
  "WorkflowState": "NEW",
  "ProductFields": {
    "StandardsArn": "arn:aws:securityhub:::standards/aws-foundational-security-best-practices/v/1.0.0"
  },
  "Resources": [{
    "Type": "AwsS3Bucket",
    "Id": "arn:aws:s3:::test-bucket-${FINDING_ID}",
    "Region": "${REGION}"
  }]
}
EOF

    # Import finding to Security Hub
    aws securityhub batch-import-findings \
        --findings file:///tmp/securityhub-finding.json \
        --region ${REGION}
    
    log_success "Security Hub finding created: ${FINDING_ID}"
    
    # Create CloudTrail event
    cat > /tmp/securityhub-event.json << EOF
{
  "version": "0",
  "id": "$(uuidgen)",
  "detail-type": "Security Hub Finding",
  "source": "aws.securityhub",
  "account": "$(aws sts get-caller-identity --query Account --output text)",
  "time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "region": "${REGION}",
  "detail": {
    "findings": [{
      "Id": "${FINDING_ID}",
      "Severity": {"Label": "CRITICAL"},
      "RecordState": "ACTIVE",
      "ProductFields": {
        "StandardsArn": "arn:aws:securityhub:::standards/aws-foundational-security-best-practices/v/1.0.0"
      },
      "Types": ["Software and Configuration Checks/AWS Security Best Practices"]
    }]
  }
}
EOF

    aws events put-events \
        --entries file:///tmp/securityhub-event.json \
        --region ${REGION}
    
    log_info "Waiting 20 seconds for Lambda to process..."
    sleep 20
    
    # Check Lambda logs
    log_info "Checking Lambda execution logs..."
    aws logs tail /aws/lambda/custodian-securityhub-critical-findings \
        --since 2m \
        --region ${REGION} \
        --format short || log_warning "No recent logs found"
    
    rm -f /tmp/securityhub-finding.json /tmp/securityhub-event.json
    log_success "Security Hub test completed"
}

test_macie_sensitive_data() {
    log_test "Testing Macie Sensitive Data Discovery Policy"
    echo "Policy: macie-sensitive-data-findings"
    echo "Lambda: custodian-macie-sensitive-data-findings"
    echo ""
    
    BUCKET_NAME="custodian-macie-test-$(date +%s)"
    
    log_info "Creating S3 bucket with test sensitive data..."
    aws s3 mb s3://${BUCKET_NAME} --region ${REGION}
    
    # Create file with fake PII
    cat > /tmp/test-pii.txt << EOF
Test Customer Data - FOR TESTING ONLY

Name: Jane Test
SSN: 555-12-3456
Credit Card: 4000-0000-0000-0002
Email: jane.test@example.com

*** This is test data only ***
EOF

    aws s3 cp /tmp/test-pii.txt s3://${BUCKET_NAME}/customer-data.txt --region ${REGION}
    
    log_success "Created test bucket: ${BUCKET_NAME}"
    
    # Simulate Macie classification event
    cat > /tmp/macie-event.json << EOF
{
  "version": "0",
  "id": "$(uuidgen)",
  "detail-type": "Macie Classification Result",
  "source": "macie2.amazonaws.com",
  "account": "$(aws sts get-caller-identity --query Account --output text)",
  "time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "region": "${REGION}",
  "detail": {
    "severity": {
      "score": 8,
      "description": "High"
    },
    "resourcesAffected": {
      "s3Bucket": {
        "name": "${BUCKET_NAME}",
        "arn": "arn:aws:s3:::${BUCKET_NAME}"
      },
      "s3Object": {
        "key": "customer-data.txt"
      }
    },
    "classificationDetails": {
      "result": {
        "status": {
          "code": "COMPLETE"
        }
      }
    }
  }
}
EOF

    aws events put-events \
        --entries file:///tmp/macie-event.json \
        --region ${REGION}
    
    log_info "Waiting 20 seconds for Lambda to process..."
    sleep 20
    
    # Check bucket protection applied
    log_info "Checking bucket protections..."
    
    ENCRYPTION=$(aws s3api get-bucket-encryption \
        --bucket ${BUCKET_NAME} \
        --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' \
        --output text 2>/dev/null || echo "Not Set")
    echo "Encryption: ${ENCRYPTION}"
    
    VERSIONING=$(aws s3api get-bucket-versioning \
        --bucket ${BUCKET_NAME} \
        --query 'Status' \
        --output text || echo "Not Set")
    echo "Versioning: ${VERSIONING}"
    
    # Check Lambda logs
    log_info "Checking Lambda execution logs..."
    aws logs tail /aws/lambda/custodian-macie-sensitive-data-findings \
        --since 2m \
        --region ${REGION} \
        --format short || log_warning "No recent logs found"
    
    # Cleanup
    log_info "Cleaning up test bucket..."
    aws s3 rb s3://${BUCKET_NAME} --force --region ${REGION} || true
    rm -f /tmp/test-pii.txt /tmp/macie-event.json
    
    log_success "Macie test completed"
}

test_iam_access_analyzer() {
    log_test "Testing IAM Access Analyzer External Access Policy"
    echo "Policy: iam-access-analyzer-external-access"
    echo "Lambda: custodian-iam-access-analyzer-external-access"
    echo ""
    
    ROLE_NAME="CustodianTestRole-$(date +%s)"
    FINDING_ID="access-analyzer-test-$(date +%s)"
    
    log_info "Creating IAM role with external access..."
    
    # Create trust policy allowing external account
    cat > /tmp/trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::123456789012:root"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

    aws iam create-role \
        --role-name ${ROLE_NAME} \
        --assume-role-policy-document file:///tmp/trust-policy.json
    
    log_success "Created role: ${ROLE_NAME}"
    
    # Simulate Access Analyzer finding event
    cat > /tmp/access-analyzer-event.json << EOF
{
  "version": "0",
  "id": "$(uuidgen)",
  "detail-type": "Access Analyzer Finding",
  "source": "access-analyzer.amazonaws.com",
  "account": "$(aws sts get-caller-identity --query Account --output text)",
  "time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "region": "${REGION}",
  "detail": {
    "id": "${FINDING_ID}",
    "status": "ACTIVE",
    "resourceType": "AWS::IAM::Role",
    "resourceArn": "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/${ROLE_NAME}",
    "principal": {
      "AWS": "123456789012"
    }
  }
}
EOF

    aws events put-events \
        --entries file:///tmp/access-analyzer-event.json \
        --region ${REGION}
    
    log_info "Waiting 15 seconds for Lambda to process..."
    sleep 15
    
    # Check Lambda logs
    log_info "Checking Lambda execution logs..."
    aws logs tail /aws/lambda/custodian-iam-access-analyzer-external-access \
        --since 2m \
        --region ${REGION} \
        --format short || log_warning "No recent logs found"
    
    # Cleanup
    log_info "Cleaning up test role..."
    aws iam delete-role --role-name ${ROLE_NAME} || true
    rm -f /tmp/trust-policy.json /tmp/access-analyzer-event.json
    
    log_success "IAM Access Analyzer test completed"
}

test_s3_access_logs() {
    log_test "Testing S3 Access Logs Suspicious Activity Policy"
    echo "Policy: s3-access-logs-suspicious-activity"
    echo "Lambda: custodian-s3-access-logs-suspicious-activity"
    echo ""
    
    BUCKET_NAME="custodian-s3-logs-test-$(date +%s)"
    
    log_info "Creating S3 bucket with access logging..."
    aws s3 mb s3://${BUCKET_NAME} --region ${REGION}
    
    # Enable server access logging
    aws s3api put-bucket-logging \
        --bucket ${BUCKET_NAME} \
        --bucket-logging-status "LoggingEnabled={TargetBucket=${BUCKET_NAME},TargetPrefix=access-logs/}" \
        --region ${REGION}
    
    # Upload suspicious files
    echo "fake passwords" > /tmp/passwords.txt
    echo "fake tokens" > /tmp/api-keys.txt
    
    aws s3 cp /tmp/passwords.txt s3://${BUCKET_NAME}/passwords.txt --region ${REGION}
    aws s3 cp /tmp/api-keys.txt s3://${BUCKET_NAME}/secret-keys.txt --region ${REGION}
    
    log_success "Created bucket with suspicious files: ${BUCKET_NAME}"
    
    # Simulate suspicious access events
    cat > /tmp/s3-access-event.json << EOF
{
  "version": "0",
  "id": "$(uuidgen)",
  "detail-type": "S3 Access Event",
  "source": "s3.amazonaws.com",
  "account": "$(aws sts get-caller-identity --query Account --output text)",
  "time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "region": "${REGION}",
  "detail": {
    "eventName": "GetObject",
    "requestParameters": {
      "bucketName": "${BUCKET_NAME}",
      "key": "passwords.txt"
    },
    "sourceIPAddress": "192.168.1.100"
  }
}
EOF

    aws events put-events \
        --entries file:///tmp/s3-access-event.json \
        --region ${REGION}
    
    log_info "Waiting 20 seconds for Lambda to process..."
    sleep 20
    
    # Check bucket tags
    log_info "Checking bucket tags..."
    TAGS=$(aws s3api get-bucket-tagging \
        --bucket ${BUCKET_NAME} \
        --query 'TagSet[?Key==`SuspiciousAccess`].Value' \
        --output text 2>/dev/null || echo "No tags")
    echo "SuspiciousAccess Tag: ${TAGS}"
    
    # Check Lambda logs
    log_info "Checking Lambda execution logs..."
    aws logs tail /aws/lambda/custodian-s3-access-logs-suspicious-activity \
        --since 2m \
        --region ${REGION} \
        --format short || log_warning "No recent logs found"
    
    # Cleanup
    log_info "Cleaning up test bucket..."
    aws s3 rb s3://${BUCKET_NAME} --force --region ${REGION} || true
    rm -f /tmp/passwords.txt /tmp/api-keys.txt /tmp/s3-access-event.json
    
    log_success "S3 Access Logs test completed"
}

test_cloudtrail_security_events() {
    log_test "Testing CloudTrail High-Risk Security Events Policy"
    echo "Policy: cloudtrail-security-events"
    echo "Lambda: custodian-cloudtrail-security-events"
    echo ""
    
    TEST_USER="custodian-test-user-$(date +%s)"
    
    log_info "Creating test IAM user..."
    aws iam create-user --user-name ${TEST_USER}
    
    # Create test policy
    cat > /tmp/test-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::test-bucket/*"
    }
  ]
}
EOF

    # Attach policy (triggers PutUserPolicy event)
    aws iam put-user-policy \
        --user-name ${TEST_USER} \
        --policy-name TestPolicy \
        --policy-document file:///tmp/test-policy.json
    
    log_success "Created test user and attached policy: ${TEST_USER}"
    
    # Simulate security events
    cat > /tmp/cloudtrail-event.json << EOF
{
  "version": "0",
  "id": "$(uuidgen)",
  "detail-type": "AWS Console Sign In",
  "source": "signin.amazonaws.com",
  "account": "$(aws sts get-caller-identity --query Account --output text)",
  "time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "region": "${REGION}",
  "detail": {
    "eventName": "ConsoleLogin",
    "userIdentity": {
      "type": "Root",
      "accountId": "$(aws sts get-caller-identity --query Account --output text)"
    },
    "responseElements": {
      "ConsoleLogin": "Failure"
    },
    "additionalEventData": {
      "MFAUsed": "No"
    },
    "sourceIPAddress": "203.0.113.12",
    "awsRegion": "${REGION}"
  }
}
EOF

    aws events put-events \
        --entries file:///tmp/cloudtrail-event.json \
        --region ${REGION}
    
    log_info "Waiting 20 seconds for Lambda to process..."
    sleep 20
    
    # Check Lambda logs
    log_info "Checking Lambda execution logs..."
    aws logs tail /aws/lambda/custodian-cloudtrail-security-events \
        --since 2m \
        --region ${REGION} \
        --format short || log_warning "No recent logs found"
    
    # Cleanup
    log_info "Cleaning up test user..."
    aws iam delete-user-policy --user-name ${TEST_USER} --policy-name TestPolicy || true
    aws iam delete-user --user-name ${TEST_USER} || true
    rm -f /tmp/test-policy.json /tmp/cloudtrail-event.json
    
    log_success "CloudTrail security events test completed"
}

test_security_summary() {
    log_test "Testing Security Findings Daily Summary Policy"
    echo "Policy: security-findings-daily-summary"
    echo "Lambda: custodian-security-findings-daily-summary"
    echo ""
    
    log_info "Triggering security findings aggregator..."
    
    # Check if aggregator exists
    if aws lambda get-function \
        --function-name custodian-security-findings-aggregator \
        --region ${REGION} &>/dev/null; then
        
        log_success "Found aggregator Lambda function"
        
        # Invoke aggregator
        aws lambda invoke \
            --function-name custodian-security-findings-aggregator \
            --region ${REGION} \
            --log-type Tail \
            /tmp/aggregator-response.json
        
        log_info "Aggregator response:"
        cat /tmp/aggregator-response.json | jq '.' 2>/dev/null || cat /tmp/aggregator-response.json
        
    else
        log_warning "Aggregator Lambda not found - simulating summary"
    fi
    
    # Trigger summary notification
    cat > /tmp/summary-event.json << EOF
{
  "version": "0",
  "id": "$(uuidgen)",
  "detail-type": "Scheduled Event",
  "source": "aws.events",
  "account": "$(aws sts get-caller-identity --query Account --output text)",
  "time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "region": "${REGION}",
  "detail": {
    "state": "SUCCEEDED"
  }
}
EOF

    aws events put-events \
        --entries file:///tmp/summary-event.json \
        --region ${REGION}
    
    log_info "Waiting 15 seconds for Lambda to process..."
    sleep 15
    
    # Check Lambda logs
    log_info "Checking Lambda execution logs..."
    aws logs tail /aws/lambda/custodian-security-findings-daily-summary \
        --since 2m \
        --region ${REGION} \
        --format short || log_warning "No recent logs found"
    
    rm -f /tmp/aggregator-response.json /tmp/summary-event.json
    log_success "Security summary test completed"
}

run_all_tests() {
    log_info "Starting comprehensive security findings test suite..."
    echo "This will test all 8 security policies and may take 20+ minutes"
    echo ""
    
    test_guardduty_findings
    echo ""
    test_config_compliance
    echo ""
    test_securityhub_findings
    echo ""
    test_macie_sensitive_data
    echo ""
    test_iam_access_analyzer
    echo ""
    test_s3_access_logs
    echo ""
    test_cloudtrail_security_events
    echo ""
    test_security_summary
    
    log_success "All security findings tests completed!"
}

cleanup_test_resources() {
    log_info "Cleaning up any remaining test resources..."
    
    # Clean up test buckets with detailed progress
    log_info "Scanning for test S3 buckets..."
    BUCKET_COUNT=0
    aws s3 ls | grep -E "(custodian-test|custodian-macie|custodian-s3-logs|custodian-suspicious)" | \
    while read -r line; do
        bucket=$(echo $line | awk '{print $3}')
        if [[ -n "$bucket" ]]; then
            log_info "Removing bucket: $bucket"
            # First empty the bucket, then delete it
            aws s3 rm s3://$bucket --recursive --region ${REGION} 2>/dev/null || true
            aws s3 rb s3://$bucket --region ${REGION} 2>/dev/null || true
            BUCKET_COUNT=$((BUCKET_COUNT + 1))
        fi
    done
    log_success "Removed $BUCKET_COUNT test buckets"
    
    # Clean up test IAM users with detailed progress
    log_info "Scanning for test IAM users..."
    USER_COUNT=0
    aws iam list-users --query 'Users[?starts_with(UserName, `custodian-test-user`)].UserName' \
        --output text | \
    while read -r user; do
        if [[ -n "$user" ]] && [[ "$user" != "None" ]]; then
            log_info "Removing IAM user: $user"
            
            # Remove access keys
            aws iam list-access-keys --user-name "$user" --query 'AccessKeyMetadata[].AccessKeyId' --output text | \
            while read -r key; do
                if [[ -n "$key" ]] && [[ "$key" != "None" ]]; then
                    aws iam delete-access-key --user-name "$user" --access-key-id "$key" 2>/dev/null || true
                fi
            done
            
            # Remove user policies
            aws iam list-user-policies --user-name "$user" --query 'PolicyNames[]' --output text | \
            while read -r policy; do
                if [[ -n "$policy" ]] && [[ "$policy" != "None" ]]; then
                    aws iam delete-user-policy --user-name "$user" --policy-name "$policy" 2>/dev/null || true
                fi
            done
            
            # Remove attached policies
            aws iam list-attached-user-policies --user-name "$user" --query 'AttachedPolicies[].PolicyArn' --output text | \
            while read -r arn; do
                if [[ -n "$arn" ]] && [[ "$arn" != "None" ]]; then
                    aws iam detach-user-policy --user-name "$user" --policy-arn "$arn" 2>/dev/null || true
                fi
            done
            
            # Delete user
            aws iam delete-user --user-name "$user" 2>/dev/null || true
            USER_COUNT=$((USER_COUNT + 1))
        fi
    done
    log_success "Removed $USER_COUNT test IAM users"
    
    # Clean up test IAM roles with detailed progress
    log_info "Scanning for test IAM roles..."
    ROLE_COUNT=0
    aws iam list-roles --query 'Roles[?starts_with(RoleName, `CustodianTestRole`)].RoleName' \
        --output text | \
    while read -r role; do
        if [[ -n "$role" ]] && [[ "$role" != "None" ]]; then
            log_info "Removing IAM role: $role"
            
            # Remove attached policies
            aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text | \
            while read -r arn; do
                if [[ -n "$arn" ]] && [[ "$arn" != "None" ]]; then
                    aws iam detach-role-policy --role-name "$role" --policy-arn "$arn" 2>/dev/null || true
                fi
            done
            
            # Remove inline policies
            aws iam list-role-policies --role-name "$role" --query 'PolicyNames[]' --output text | \
            while read -r policy; do
                if [[ -n "$policy" ]] && [[ "$policy" != "None" ]]; then
                    aws iam delete-role-policy --role-name "$role" --policy-name "$policy" 2>/dev/null || true
                fi
            done
            
            # Delete role
            aws iam delete-role --role-name "$role" 2>/dev/null || true
            ROLE_COUNT=$((ROLE_COUNT + 1))
        fi
    done
    log_success "Removed $ROLE_COUNT test IAM roles"
    
    # Clean up Security Hub test findings
    log_info "Cleaning up Security Hub test findings..."
    FINDINGS_COUNT=0
    TEST_FINDINGS=$(aws securityhub get-findings \
        --filters '{"Title": [{"Value": "[TEST]", "Comparison": "PREFIX"}], "Title": [{"Value": "[DEMO]", "Comparison": "PREFIX"}]}' \
        --query 'Findings[].Id' \
        --output text \
        --region ${REGION} 2>/dev/null || echo "")
    
    if [[ -n "$TEST_FINDINGS" ]] && [[ "$TEST_FINDINGS" != "None" ]]; then
        echo "$TEST_FINDINGS" | while read -r finding_id; do
            if [[ -n "$finding_id" ]]; then
                log_info "Archiving test finding: $finding_id"
                aws securityhub batch-update-findings \
                    --finding-identifiers Id="$finding_id",ProductArn="arn:aws:securityhub:${REGION}:$(aws sts get-caller-identity --query Account --output text):product/aws/securityhub" \
                    --workflow Status=RESOLVED,ReasonCode=TEST_COMPLETED \
                    --region ${REGION} 2>/dev/null || true
                FINDINGS_COUNT=$((FINDINGS_COUNT + 1))
            fi
        done
        log_success "Archived $FINDINGS_COUNT test findings"
    else
        log_success "No test findings to clean up"
    fi
    
    # Clean up temp files
    log_info "Cleaning up temporary files..."
    rm -f /tmp/guardduty-test-event.json
    rm -f /tmp/config-test-event.json
    rm -f /tmp/securityhub-*.json
    rm -f /tmp/macie-event.json
    rm -f /tmp/test-pii.txt
    rm -f /tmp/trust-policy.json
    rm -f /tmp/access-analyzer-event.json
    rm -f /tmp/s3-access-event.json
    rm -f /tmp/passwords.txt
    rm -f /tmp/api-keys.txt
    rm -f /tmp/test-policy.json
    rm -f /tmp/cloudtrail-event.json
    rm -f /tmp/summary-event.json
    rm -f /tmp/aggregator-response.json
    rm -f /tmp/sensitive-data.txt
    rm -f /tmp/test-*.json
    log_success "Temporary files cleaned"
    
    # Summary
    echo ""
    log_success "Cleanup completed successfully!"
    echo ""
    echo "📊 Cleanup Summary:"
    echo "  🗑️ S3 buckets: Removed test buckets"
    echo "  🗑️ IAM users: Removed test users and access keys"
    echo "  🗑️ IAM roles: Removed test roles and policies"
    echo "  🗑️ Security Hub: Archived test findings"
    echo "  🗑️ Files: Removed temporary test files"
    echo ""
    echo "💡 To verify cleanup completion:"
    echo "   - Check AWS Console for remaining resources"
    echo "   - Re-run this script to confirm no test resources remain"
}

force_cleanup_all_resources() {
    log_warning "🗑️ FORCE CLEANUP - ALL DEMO RESOURCES"
    echo "════════════════════════════════════════════════════════════"
    echo "⚠️ WARNING: This will aggressively remove ALL demo/test resources!"
    echo "This includes:"
    echo "  • All S3 buckets with 'custodian', 'test', or 'demo' in name"
    echo "  • All EC2 instances with TestResource tag or demo names"
    echo "  • All IAM users/roles starting with test/demo/custodian prefixes"
    echo "  • All EBS volumes and snapshots with TestResource tag"
    echo "  • All test RDS instances"
    echo "  • All test Security Hub findings"
    echo ""
    read -p "Are you sure? Type 'DELETE-ALL' to confirm: " confirm
    
    if [[ "$confirm" != "DELETE-ALL" ]]; then
        log_info "Cleanup cancelled"
        return
    fi
    
    log_warning "Starting aggressive cleanup..."
    
    # 1. S3 buckets - more aggressive matching
    log_info "📦 Force cleaning S3 buckets..."
    aws s3 ls | grep -E "(custodian|test|demo)" | while read -r line; do
        bucket=$(echo $line | awk '{print $3}')
        if [[ -n "$bucket" ]] && [[ "$bucket" != "aws-cloudtrail-logs"* ]] && [[ "$bucket" != "aws-config-bucket"* ]]; then
            log_info "  🗑️ Force removing bucket: $bucket"
            # Disable versioning
            aws s3api put-bucket-versioning --bucket "$bucket" --versioning-configuration Status=Suspended 2>/dev/null || true
            # Delete all versions
            aws s3api list-object-versions --bucket "$bucket" --output text --query 'Versions[].{Key:Key,VersionId:VersionId}' 2>/dev/null | while read key version; do
                if [[ -n "$key" ]] && [[ -n "$version" ]]; then
                    aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version" 2>/dev/null || true
                fi
            done
            # Delete delete markers
            aws s3api list-object-versions --bucket "$bucket" --output text --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' 2>/dev/null | while read key version; do
                if [[ -n "$key" ]] && [[ -n "$version" ]]; then
                    aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version" 2>/dev/null || true
                fi
            done
            # Force delete all current objects
            aws s3 rm s3://$bucket --recursive --region ${REGION} 2>/dev/null || true
            # Remove bucket
            aws s3 rb s3://$bucket --region ${REGION} 2>/dev/null || true
        fi
    done
    
    # 2. EC2 instances - more aggressive matching
    log_info "🖥️ Force terminating EC2 instances..."
    # Instances with TestResource tag
    aws ec2 describe-instances \
        --filters "Name=tag:TestResource,Values=true" \
        --query 'Reservations[].Instances[?State.Name!=`terminated`].InstanceId' \
        --output text \
        --region ${REGION} | while read instance; do
        if [[ -n "$instance" ]]; then
            log_info "  🗑️ Force terminating: $instance"
            aws ec2 terminate-instances --instance-ids $instance --region ${REGION} || true
        fi
    done
    
    # Instances with demo-related names
    aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=*custodian*,*test*,*demo*" \
        --query 'Reservations[].Instances[?State.Name!=`terminated`].InstanceId' \
        --output text \
        --region ${REGION} | while read instance; do
        if [[ -n "$instance" ]]; then
            log_info "  🗑️ Force terminating named: $instance"
            aws ec2 terminate-instances --instance-ids $instance --region ${REGION} || true
        fi
    done
    
    # 3. Wait for terminations and clean volumes
    log_info "⏳ Waiting 60 seconds for EC2 terminations..."
    sleep 60
    
    # EBS volumes
    log_info "💽 Force cleaning EBS volumes..."
    aws ec2 describe-volumes \
        --filters "Name=tag:TestResource,Values=true" "Name=state,Values=available" \
        --query 'Volumes[].VolumeId' \
        --output text \
        --region ${REGION} | while read volume; do
        if [[ -n "$volume" ]]; then
            log_info "  🗑️ Force deleting volume: $volume"
            aws ec2 delete-volume --volume-id $volume --region ${REGION} || true
        fi
    done
    
    # EBS snapshots
    log_info "📸 Force cleaning EBS snapshots..."
    aws ec2 describe-snapshots \
        --owner-ids self \
        --filters "Name=tag:TestResource,Values=true" \
        --query 'Snapshots[].SnapshotId' \
        --output text \
        --region ${REGION} | while read snapshot; do
        if [[ -n "$snapshot" ]]; then
            log_info "  🗑️ Force deleting snapshot: $snapshot"
            aws ec2 delete-snapshot --snapshot-id $snapshot --region ${REGION} || true
        fi
    done
    
    # Also delete snapshots with demo descriptions
    aws ec2 describe-snapshots \
        --owner-ids self \
        --filters "Name=description,Values=*custodian*,*test*,*demo*" \
        --query 'Snapshots[].SnapshotId' \
        --output text \
        --region ${REGION} | while read snapshot; do
        if [[ -n "$snapshot" ]]; then
            log_info "  🗑️ Force deleting demo snapshot: $snapshot"
            aws ec2 delete-snapshot --snapshot-id $snapshot --region ${REGION} || true
        fi
    done
    
    # 4. IAM users - aggressive cleanup
    log_info "👤 Force cleaning IAM users..."
    aws iam list-users --query 'Users[?starts_with(UserName, `custodian-test`) || starts_with(UserName, `test-`) || starts_with(UserName, `demo-`)].UserName' --output text | while read -r user; do
        if [[ -n "$user" ]]; then
            log_info "  🗑️ Force removing user: $user"
            # Remove all user policies
            aws iam list-user-policies --user-name "$user" --query 'PolicyNames[]' --output text | while read -r policy; do
                if [[ -n "$policy" ]]; then
                    aws iam delete-user-policy --user-name "$user" --policy-name "$policy" 2>/dev/null || true
                fi
            done
            # Detach all attached policies
            aws iam list-attached-user-policies --user-name "$user" --query 'AttachedPolicies[].PolicyArn' --output text | while read -r policy; do
                if [[ -n "$policy" ]]; then
                    aws iam detach-user-policy --user-name "$user" --policy-arn "$policy" 2>/dev/null || true
                fi
            done
            # Remove all access keys
            aws iam list-access-keys --user-name "$user" --query 'AccessKeyMetadata[].AccessKeyId' --output text | while read -r key; do
                if [[ -n "$key" ]]; then
                    aws iam delete-access-key --user-name "$user" --access-key-id "$key" 2>/dev/null || true
                fi
            done
            # Remove from all groups
            aws iam get-groups-for-user --user-name "$user" --query 'Groups[].GroupName' --output text 2>/dev/null | while read -r group; do
                if [[ -n "$group" ]]; then
                    aws iam remove-user-from-group --user-name "$user" --group-name "$group" 2>/dev/null || true
                fi
            done
            # Delete user
            aws iam delete-user --user-name "$user" 2>/dev/null || true
        fi
    done
    
    # 5. IAM roles - aggressive cleanup
    log_info "🔐 Force cleaning IAM roles..."
    aws iam list-roles --query 'Roles[?starts_with(RoleName, `CustodianTestRole`) || starts_with(RoleName, `custodian-test`) || starts_with(RoleName, `test-`) || starts_with(RoleName, `demo-`)].RoleName' --output text | while read -r role; do
        if [[ -n "$role" ]]; then
            log_info "  🗑️ Force removing role: $role"
            # Detach all managed policies
            aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text | while read -r policy; do
                if [[ -n "$policy" ]]; then
                    aws iam detach-role-policy --role-name "$role" --policy-arn "$policy" 2>/dev/null || true
                fi
            done
            # Remove all inline policies
            aws iam list-role-policies --role-name "$role" --query 'PolicyNames[]' --output text | while read -r policy; do
                if [[ -n "$policy" ]]; then
                    aws iam delete-role-policy --role-name "$role" --policy-name "$policy" 2>/dev/null || true
                fi
            done
            # Remove from instance profiles
            aws iam list-instance-profiles-for-role --role-name "$role" --query 'InstanceProfiles[].InstanceProfileName' --output text 2>/dev/null | while read -r profile; do
                if [[ -n "$profile" ]]; then
                    aws iam remove-role-from-instance-profile --instance-profile-name "$profile" --role-name "$role" 2>/dev/null || true
                    aws iam delete-instance-profile --instance-profile-name "$profile" 2>/dev/null || true
                fi
            done
            # Delete role
            aws iam delete-role --role-name "$role" 2>/dev/null || true
        fi
    done
    
    # 6. RDS instances
    log_info "🗄️ Force cleaning RDS instances..."
    aws rds describe-db-instances --query 'DBInstances[?starts_with(DBInstanceIdentifier, `custodian-test`)].DBInstanceIdentifier' --output text --region ${REGION} | while read -r db; do
        if [[ -n "$db" ]]; then
            log_info "  🗑️ Force deleting RDS: $db"
            aws rds delete-db-instance \
                --db-instance-identifier "$db" \
                --skip-final-snapshot \
                --delete-automated-backups \
                --region ${REGION} 2>/dev/null || true
        fi
    done
    
    # 7. Security Hub findings
    log_info "🔒 Archiving test Security Hub findings..."
    aws securityhub get-findings \
        --filters '{"Title": [{"Value": "[TEST]", "Comparison": "PREFIX"}], "Title": [{"Value": "[DEMO]", "Comparison": "PREFIX"}]}' \
        --query 'Findings[].Id' --output text --region ${REGION} 2>/dev/null | while read -r finding; do
        if [[ -n "$finding" ]]; then
            log_info "  🗑️ Archiving finding: $finding"
            aws securityhub batch-update-findings \
                --finding-identifiers Id="$finding",ProductArn="arn:aws:securityhub:${REGION}:$(aws sts get-caller-identity --query Account --output text):product/aws/securityhub" \
                --workflow Status="RESOLVED" \
                --region ${REGION} 2>/dev/null || true
        fi
    done
    
    # 8. Clean all temp files
    log_info "📁 Force cleaning temporary files..."
    rm -f /tmp/*test*.json /tmp/*demo*.json /tmp/*custodian*.json
    rm -f /tmp/*guardduty*.json /tmp/*config*.json /tmp/*securityhub*.json
    rm -f /tmp/*macie*.json /tmp/*access*.json /tmp/*s3*.json
    rm -f /tmp/*cloudtrail*.json /tmp/*summary*.json /tmp/*aggregator*.json
    rm -f /tmp/*pii*.txt /tmp/*sensitive*.txt /tmp/*secret*.txt
    rm -f /tmp/passwords.txt /tmp/api-keys.txt /tmp/test-policy.json
    rm -f /tmp/trust-policy.json
    
    log_success "Force cleanup completed!"
    echo ""
    log_info "📊 Verification recommended - run scan option to check results"
}

scan_and_report_resources() {
    log_info "🔍 RESOURCE SCAN AND REPORT"
    echo "════════════════════════════════════════════════════════════"
    echo "Scanning for all demo and test resources (read-only)"
    echo ""
    
    # Counters
    local total_resources=0
    local billable_resources=0
    
    # 1. S3 buckets scan
    echo -e "${BLUE}📦 S3 Buckets:${NC}"
    echo "─────────────────────────────────────────────────"
    local bucket_count=0
    aws s3 ls | grep -E "(custodian|test|demo)" | while read -r line; do
        bucket=$(echo $line | awk '{print $3}')
        if [[ -n "$bucket" ]]; then
            size=$(aws s3 ls s3://$bucket --recursive --summarize 2>/dev/null | grep "Total Size" | awk '{print $3 " " $4}' || echo "unknown")
            objects=$(aws s3 ls s3://$bucket --recursive --summarize 2>/dev/null | grep "Total Objects" | awk '{print $3}' || echo "unknown")
            echo "  📦 $bucket (Size: $size, Objects: $objects)"
            bucket_count=$((bucket_count + 1))
        fi
    done
    
    if [[ $bucket_count -eq 0 ]]; then
        echo "  ✅ No demo/test S3 buckets found"
    else
        echo "  📊 Total buckets: $bucket_count"
        total_resources=$((total_resources + bucket_count))
        billable_resources=$((billable_resources + bucket_count))
    fi
    echo ""
    
    # 2. EC2 instances scan
    echo -e "${BLUE}🖥️ EC2 Instances:${NC}"
    echo "─────────────────────────────────────────────────"
    local instance_count=0
    local running_count=0
    aws ec2 describe-instances \
        --filters "Name=tag:TestResource,Values=true" \
        --query 'Reservations[].Instances[].[InstanceId,State.Name,InstanceType,Tags[?Key==`Name`].Value|[0],LaunchTime]' \
        --output text \
        --region ${REGION} | while read -r id state type name launch_time; do
        echo "  🖥️ $id ($state) - $type - $name - $launch_time"
        instance_count=$((instance_count + 1))
        if [[ "$state" == "running" ]]; then
            running_count=$((running_count + 1))
        fi
    done
    
    if [[ $instance_count -eq 0 ]]; then
        echo "  ✅ No test EC2 instances found"
    else
        echo "  📊 Total instances: $instance_count (Running: $running_count)"
        total_resources=$((total_resources + instance_count))
        billable_resources=$((billable_resources + running_count))
    fi
    echo ""
    
    # 3. EBS volumes scan
    echo -e "${BLUE}💽 EBS Volumes:${NC}"
    echo "─────────────────────────────────────────────────"
    local volume_count=0
    local available_count=0
    aws ec2 describe-volumes \
        --filters "Name=tag:TestResource,Values=true" \
        --query 'Volumes[].[VolumeId,State,Size,VolumeType,CreateTime]' \
        --output text \
        --region ${REGION} | while read -r id state size type create_time; do
        echo "  💽 $id ($state) - ${size}GB $type - $create_time"
        volume_count=$((volume_count + 1))
        if [[ "$state" == "available" ]]; then
            available_count=$((available_count + 1))
        fi
    done
    
    if [[ $volume_count -eq 0 ]]; then
        echo "  ✅ No test EBS volumes found"
    else
        echo "  📊 Total volumes: $volume_count (Available: $available_count)"
        total_resources=$((total_resources + volume_count))
        billable_resources=$((billable_resources + available_count))
    fi
    echo ""
    
    # 4. EBS snapshots scan
    echo -e "${BLUE}📸 EBS Snapshots:${NC}"
    echo "─────────────────────────────────────────────────"
    local snapshot_count=0
    aws ec2 describe-snapshots \
        --owner-ids self \
        --filters "Name=tag:TestResource,Values=true" \
        --query 'Snapshots[].[SnapshotId,State,VolumeSize,Description,StartTime]' \
        --output text \
        --region ${REGION} | while read -r id state size desc start_time; do
        echo "  📸 $id ($state) - ${size}GB - $desc - $start_time"
        snapshot_count=$((snapshot_count + 1))
    done
    
    if [[ $snapshot_count -eq 0 ]]; then
        echo "  ✅ No test EBS snapshots found"
    else
        echo "  📊 Total snapshots: $snapshot_count"
        total_resources=$((total_resources + snapshot_count))
        billable_resources=$((billable_resources + snapshot_count))
    fi
    echo ""
    
    # 5. IAM users scan
    echo -e "${BLUE}👤 IAM Users:${NC}"
    echo "─────────────────────────────────────────────────"
    local user_count=0
    aws iam list-users --query 'Users[?starts_with(UserName, `custodian-test`) || starts_with(UserName, `test-`) || starts_with(UserName, `demo-`)].UserName' --output text | while read -r user; do
        if [[ -n "$user" ]]; then
            policies=$(aws iam list-attached-user-policies --user-name "$user" --query 'length(AttachedPolicies)' --output text 2>/dev/null || echo "0")
            inline_policies=$(aws iam list-user-policies --user-name "$user" --query 'length(PolicyNames)' --output text 2>/dev/null || echo "0")
            keys=$(aws iam list-access-keys --user-name "$user" --query 'length(AccessKeyMetadata)' --output text 2>/dev/null || echo "0")
            echo "  👤 $user (Managed: $policies, Inline: $inline_policies, Keys: $keys)"
            user_count=$((user_count + 1))
        fi
    done
    
    if [[ $user_count -eq 0 ]]; then
        echo "  ✅ No test IAM users found"
    else
        echo "  📊 Total users: $user_count"
        total_resources=$((total_resources + user_count))
    fi
    echo ""
    
    # 6. IAM roles scan
    echo -e "${BLUE}🔐 IAM Roles:${NC}"
    echo "─────────────────────────────────────────────────"
    local role_count=0
    aws iam list-roles --query 'Roles[?starts_with(RoleName, `CustodianTestRole`) || starts_with(RoleName, `custodian-test`) || starts_with(RoleName, `test-`) || starts_with(RoleName, `demo-`)].RoleName' --output text | while read -r role; do
        if [[ -n "$role" ]]; then
            policies=$(aws iam list-attached-role-policies --role-name "$role" --query 'length(AttachedPolicies)' --output text 2>/dev/null || echo "0")
            inline_policies=$(aws iam list-role-policies --role-name "$role" --query 'length(PolicyNames)' --output text 2>/dev/null || echo "0")
            echo "  🔐 $role (Managed: $policies, Inline: $inline_policies)"
            role_count=$((role_count + 1))
        fi
    done
    
    if [[ $role_count -eq 0 ]]; then
        echo "  ✅ No test IAM roles found"
    else
        echo "  📊 Total roles: $role_count"
        total_resources=$((total_resources + role_count))
    fi
    echo ""
    
    # 7. RDS instances scan
    echo -e "${BLUE}🗄️ RDS Instances:${NC}"
    echo "─────────────────────────────────────────────────"
    local rds_count=0
    aws rds describe-db-instances --query 'DBInstances[?starts_with(DBInstanceIdentifier, `custodian-test`)].DBInstanceIdentifier' --output text --region ${REGION} | while read -r db; do
        if [[ -n "$db" ]]; then
            status=$(aws rds describe-db-instances --db-instance-identifier "$db" --query 'DBInstances[0].DBInstanceStatus' --output text --region ${REGION} 2>/dev/null || echo "unknown")
            class=$(aws rds describe-db-instances --db-instance-identifier "$db" --query 'DBInstances[0].DBInstanceClass' --output text --region ${REGION} 2>/dev/null || echo "unknown")
            echo "  🗄️ $db ($status) - $class"
            rds_count=$((rds_count + 1))
        fi
    done
    
    if [[ $rds_count -eq 0 ]]; then
        echo "  ✅ No test RDS instances found"
    else
        echo "  📊 Total RDS instances: $rds_count"
        total_resources=$((total_resources + rds_count))
        billable_resources=$((billable_resources + rds_count))
    fi
    echo ""
    
    # 8. Security Hub findings scan
    echo -e "${BLUE}🔒 Security Hub Test Findings:${NC}"
    echo "─────────────────────────────────────────────────"
    local findings_count=$(aws securityhub get-findings \
        --filters '{"Title": [{"Value": "[TEST]", "Comparison": "PREFIX"}], "Title": [{"Value": "[DEMO]", "Comparison": "PREFIX"}]}' \
        --query 'length(Findings)' --output text --region ${REGION} 2>/dev/null || echo "0")
    
    if [[ $findings_count -eq 0 ]]; then
        echo "  ✅ No test Security Hub findings found"
    else
        echo "  🔒 Test findings: $findings_count"
        total_resources=$((total_resources + findings_count))
    fi
    echo ""
    
    # 9. Summary and recommendations
    echo -e "${PURPLE}📊 SCAN SUMMARY:${NC}"
    echo "═════════════════════════════════════════════════"
    echo "  📋 Total resources found: $total_resources"
    echo "  💰 Potentially billable resources: $billable_resources"
    echo ""
    
    if [[ $total_resources -eq 0 ]]; then
        log_success "🎉 No demo/test resources found - account is clean!"
    elif [[ $billable_resources -eq 0 ]]; then
        log_info "💡 Demo resources found but no billable resources detected"
        echo "     You may want to clean up for organization purposes"
    else
        log_warning "⚠️ $billable_resources billable resources detected!"
        echo "     These may incur AWS charges if left running"
    fi
    
    echo ""
    echo -e "${PURPLE}🎯 RECOMMENDATIONS:${NC}"
    echo "─────────────────────────────────────────────────"
    
    if [[ $total_resources -gt 0 ]]; then
        echo "  1. 🧹 For security test resources only:"
        echo "     ./test-security-findings.sh cleanup"
        echo ""
        echo "  2. 🗑️ For comprehensive cleanup (ALL resources):"
        echo "     ./test-security-findings.sh force-cleanup"
        echo ""
        echo "  3. 📊 Monitor costs:"
        echo "     Check AWS Cost Explorer for demo-related charges"
    else
        echo "  ✅ No action needed - account is clean!"
    fi
    
    echo ""
    echo "📋 Scan completed at $(date)"
    echo "════════════════════════════════════════════════════════════"
}

cleanup_test_resources() {
    log_info "Cleaning up any remaining test resources..."

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -eq 0 ]]; then
        # Interactive mode
        while true; do
            show_menu
            read -p "Select option: " choice
            case $choice in
                1) test_guardduty_findings ;;
                2) test_config_compliance ;;
                3) test_securityhub_findings ;;
                4) test_macie_sensitive_data ;;
                5) test_iam_access_analyzer ;;
                6) test_s3_access_logs ;;
                7) test_cloudtrail_security_events ;;
                8) test_security_summary ;;
                9) run_all_tests ;;
                10) cleanup_test_resources ;;
                11) force_cleanup_all_resources ;;
                12) scan_and_report_resources ;;
                q|Q) log_info "Exiting..."; exit 0 ;;
                *) log_error "Invalid option. Please try again." ;;
            esac
            echo ""
            read -p "Press Enter to continue..."
        done
    else
        # Command line mode
        case $1 in
            guardduty) test_guardduty_findings ;;
            config) test_config_compliance ;;
            securityhub) test_securityhub_findings ;;
            macie) test_macie_sensitive_data ;;
            accessanalyzer) test_iam_access_analyzer ;;
            s3logs) test_s3_access_logs ;;
            cloudtrail) test_cloudtrail_security_events ;;
            summary) test_security_summary ;;
            all) run_all_tests ;;
            cleanup) cleanup_test_resources ;;
            force-cleanup) force_cleanup_all_resources ;;
            scan) scan_and_report_resources ;;
            *) 
                echo "Usage: $0 [guardduty|config|securityhub|macie|accessanalyzer|s3logs|cloudtrail|summary|all|cleanup|force-cleanup|scan]"
                exit 1
                ;;
        esac
    fi
fi