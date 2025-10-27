#!/bin/bash

# Cloud Custodian Security Hub Demo
# This script creates real security findings that Security Hub will detect

set -e

# Configuration
REGION="${AWS_REGION:-us-east-1}"
DEMO_PREFIX="custodian-securityhub-demo"
DEMO_TAG_KEY="CustodianDemo"
DEMO_TAG_VALUE="SecurityHubTest"
MONITORING_DURATION="${MONITORING_DURATION:-15}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

cleanup_resources() {
    log_info "🧹 Cleaning up Security Hub demo resources..."
    
    # Delete demo S3 buckets
    local buckets=$(aws s3api list-buckets \
        --query "Buckets[?contains(Name, 'securityhub-test') || contains(Name, 'security-demo-bucket')].Name" \
        --output text 2>/dev/null || echo "")
    
    for bucket in $buckets; do
        if [[ -n "$bucket" && "$bucket" != "None" ]]; then
            log_info "Deleting bucket: $bucket"
            aws s3 rb s3://$bucket --force --region "$REGION" || true
        fi
    done
    
    # Delete demo IAM users
    local users=$(aws iam list-users \
        --query "Users[?contains(UserName, 'securityhub-test')].UserName" \
        --output text 2>/dev/null || echo "")
    
    for user in $users; do
        if [[ -n "$user" && "$user" != "None" ]]; then
            log_info "Deleting IAM user: $user"
            # Delete access keys
            local keys=$(aws iam list-access-keys \
                --user-name "$user" \
                --query 'AccessKeyMetadata[].AccessKeyId' \
                --output text 2>/dev/null || echo "")
            
            for key in $keys; do
                aws iam delete-access-key --user-name "$user" --access-key-id "$key" || true
            done
            
            # Delete user policies
            local policies=$(aws iam list-user-policies \
                --user-name "$user" \
                --query 'PolicyNames[]' \
                --output text 2>/dev/null || echo "")
            
            for policy in $policies; do
                aws iam delete-user-policy --user-name "$user" --policy-name "$policy" || true
            done
            
            aws iam delete-user --user-name "$user" || true
        fi
    done
    
    # Delete demo security groups
    local security_groups=$(aws ec2 describe-security-groups \
        --region "$REGION" \
        --filters "Name=tag:$DEMO_TAG_KEY,Values=$DEMO_TAG_VALUE" \
        --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
        --output text 2>/dev/null || echo "")
    
    for sg in $security_groups; do
        if [[ -n "$sg" && "$sg" != "None" ]]; then
            log_info "Deleting security group: $sg"
            aws ec2 delete-security-group --region "$REGION" --group-id "$sg" || true
        fi
    done
    
    log_success "Security Hub demo cleanup completed"
}

check_securityhub_status() {
    log_info "🔍 Checking Security Hub status..."
    
    # Check if Security Hub is enabled
    local hub_arn=$(aws securityhub describe-hub \
        --region "$REGION" \
        --query 'HubArn' \
        --output text 2>/dev/null || echo "None")
    
    if [[ "$hub_arn" == "None" || -z "$hub_arn" ]]; then
        log_warning "Security Hub is not enabled in region $REGION"
        log_info "Enabling Security Hub..."
        
        aws securityhub enable-security-hub \
            --enable-default-standards \
            --region "$REGION"
        
        # Wait for initialization
        sleep 30
        
        log_success "Security Hub enabled in region $REGION"
    else
        log_success "Security Hub is already enabled: $hub_arn"
    fi
    
    # Check standards subscriptions
    local standards=$(aws securityhub get-enabled-standards \
        --region "$REGION" \
        --query 'StandardsSubscriptions[].StandardsArn' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$standards" && "$standards" != "None" ]]; then
        log_success "Security standards enabled: $(echo $standards | wc -w) standards"
    else
        log_info "Enabling AWS Foundational Security Standard..."
        
        local aws_standard_arn="arn:aws:securityhub:::ruleset/finding-format/aws-foundational-security"
        aws securityhub batch-enable-standards \
            --standards-subscription-requests StandardsArn=$aws_standard_arn \
            --region "$REGION" || true
    fi
}

create_security_violations() {
    log_info "🚀 Creating real security violations for Security Hub to detect..."
    
    # Violation 1: Unencrypted S3 bucket (violates S3.4)
    local bucket_name="securityhub-test-unencrypted-$(date +%s)"
    
    log_info "📦 Creating unencrypted S3 bucket..."
    aws s3 mb s3://$bucket_name --region "$REGION"
    
    # Make bucket public to violate S3.1 as well
    log_warning "🔓 Making bucket public (Security Hub violations)..."
    aws s3api put-bucket-acl \
        --bucket "$bucket_name" \
        --acl public-read \
        --region "$REGION"
    
    # Add public bucket policy
    cat > /tmp/public-bucket-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": ["arn:aws:s3:::$bucket_name/*", "arn:aws:s3:::$bucket_name"]
    }
  ]
}
EOF
    
    aws s3api put-bucket-policy \
        --bucket "$bucket_name" \
        --policy file:///tmp/public-bucket-policy.json \
        --region "$REGION"
    
    log_success "Created unencrypted public S3 bucket: $bucket_name"
    
    # Violation 2: Security group with unrestricted access (violates EC2.19)
    log_info "🌐 Creating unrestricted security group..."
    
    local vpc_id=$(aws ec2 describe-vpcs \
        --region "$REGION" \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' \
        --output text)
    
    local sg_id=""
    if [[ "$vpc_id" != "None" && -n "$vpc_id" ]]; then
        sg_id=$(aws ec2 create-security-group \
            --region "$REGION" \
            --group-name "$DEMO_PREFIX-unrestricted-sg" \
            --description "Unrestricted security group for Security Hub demo" \
            --vpc-id "$vpc_id" \
            --tag-specifications "ResourceType=security-group,Tags=[{Key=$DEMO_TAG_KEY,Value=$DEMO_TAG_VALUE}]" \
            --query 'GroupId' \
            --output text)
        
        # Add unrestricted SSH access (violates EC2.19)
        aws ec2 authorize-security-group-ingress \
            --region "$REGION" \
            --group-id "$sg_id" \
            --protocol tcp \
            --port 22 \
            --cidr 0.0.0.0/0
        
        # Add unrestricted HTTP access
        aws ec2 authorize-security-group-ingress \
            --region "$REGION" \
            --group-id "$sg_id" \
            --protocol tcp \
            --port 80 \
            --cidr 0.0.0.0/0
        
        # Add unrestricted database access (very dangerous)
        aws ec2 authorize-security-group-ingress \
            --region "$REGION" \
            --group-id "$sg_id" \
            --protocol tcp \
            --port 3306 \
            --cidr 0.0.0.0/0
        
        log_success "Created unrestricted security group: $sg_id"
    fi
    
    # Violation 3: IAM user without MFA (violates IAM.6)
    log_info "👤 Creating IAM user without MFA..."
    
    local iam_user="securityhub-test-user-$(date +%s)"
    
    aws iam create-user --user-name "$iam_user" --region "$REGION"
    
    # Create access key (additional security risk)
    local access_key_info=$(aws iam create-access-key \
        --user-name "$iam_user" \
        --query 'AccessKey.AccessKeyId' \
        --output text)
    
    # Attach policy that grants some permissions (makes the user active)
    cat > /tmp/test-user-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetObject"
      ],
      "Resource": "*"
    }
  ]
}
EOF
    
    aws iam put-user-policy \
        --user-name "$iam_user" \
        --policy-name "TestUserPolicy" \
        --policy-document file:///tmp/test-user-policy.json \
        --region "$REGION"
    
    log_success "Created IAM user without MFA: $iam_user"
    
    rm -f /tmp/public-bucket-policy.json /tmp/test-user-policy.json
    
    echo "$bucket_name,$sg_id,$iam_user,$access_key_info"
}

monitor_securityhub_findings() {
    local bucket_name="$1"
    local sg_id="$2"
    local iam_user="$3"
    local duration="$4"
    
    log_info "📊 Monitoring Security Hub findings for $duration minutes..."
    
    local end_time=$(($(date +%s) + duration * 60))
    local check_count=0
    
    while [[ $(date +%s) -lt $end_time ]]; do
        check_count=$((check_count + 1))
        
        log_info "Check #$check_count - Looking for Security Hub findings..."
        
        # Get findings from last hour
        local findings=$(aws securityhub get-findings \
            --region "$REGION" \
            --filters '{"UpdatedAt":[{"Start":"'$(date -d '1 hour ago' --iso-8601)'","End":"'$(date --iso-8601)'"}]}' \
            --query 'Findings[].{Id:Id,Title:Title,Severity:Severity.Label,Compliance:Compliance.Status}' \
            --output table 2>/dev/null || echo "")
        
        if [[ -n "$findings" && "$findings" != "None" && $(echo "$findings" | wc -l) -gt 5 ]]; then
            log_success "🚨 Found Security Hub findings!"
            echo "$findings"
            break
        else
            log_info "No new findings yet... (Security Hub needs time to evaluate)"
        fi
        
        sleep 60
    done
}

generate_demo_report() {
    local bucket_name="$1"
    local sg_id="$2"
    local iam_user="$3"
    local access_key="$4"
    
    log_info "📋 Generating Security Hub Demo Report..."
    
    cat << EOF

🔒 Security Hub Demo Report
════════════════════════════════════════════════════════════════════════

📊 Demo Summary:
  • Region: $REGION
  • Demo Duration: $MONITORING_DURATION minutes
  • Demo Resources Created: 3

🚨 Security Violations Created:
  • Unencrypted public S3 bucket: $bucket_name
  • Unrestricted security group: $sg_id
  • IAM user without MFA: $iam_user (Access Key: $access_key)

⚠️ Expected Security Hub Findings:
  • S3.4: S3 buckets should have server-side encryption enabled
  • S3.1: S3 bucket public access should be restricted
  • EC2.19: Security groups should not allow unrestricted access
  • IAM.6: Hardware MFA should be enabled for root user

🔍 Next Steps:
  1. Check AWS Security Hub console for findings
  2. Review Cloud Custodian policies for automated remediation
  3. Monitor for 15-30 minutes for complete evaluation

🧹 Cleanup:
  Run: $0 --cleanup
  Or manually delete resources with tag: $DEMO_TAG_KEY=$DEMO_TAG_VALUE

EOF
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Security Hub Demo Script - Creates security violations for Security Hub testing

OPTIONS:
    --region REGION         AWS region (default: us-east-1)
    --duration MINUTES      Monitoring duration in minutes (default: 15)
    --cleanup              Clean up demo resources and exit
    --check-only           Only check Security Hub status
    --help                 Show this help message

EXAMPLES:
    $0                           # Run full demo with defaults
    $0 --region us-west-2        # Run demo in us-west-2
    $0 --duration 30             # Monitor for 30 minutes
    $0 --cleanup                 # Clean up all demo resources
    $0 --check-only              # Just check Security Hub status

WARNING: This script creates real AWS resources that may incur costs.

EOF
}

main() {
    local cleanup_only=false
    local check_only=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --region)
                REGION="$2"
                shift 2
                ;;
            --duration)
                MONITORING_DURATION="$2"
                shift 2
                ;;
            --cleanup)
                cleanup_only=true
                shift
                ;;
            --check-only)
                check_only=true
                shift
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    log_info "🔒 Cloud Custodian Security Hub Demo"
    log_info "Region: $REGION"
    log_info "Monitoring Duration: $MONITORING_DURATION minutes"
    echo ""
    
    # Cleanup mode
    if [[ "$cleanup_only" == true ]]; then
        cleanup_resources
        log_success "🧹 Cleanup completed"
        exit 0
    fi
    
    # Check Security Hub status
    check_securityhub_status
    
    if [[ "$check_only" == true ]]; then
        log_success "✅ Security Hub check completed"
        exit 0
    fi
    
    # Trap to cleanup on exit
    trap cleanup_resources EXIT
    
    log_warning "⚠️ WARNING: This demo will create security violations!"
    log_warning "⚠️ These resources will be flagged by Security Hub"
    log_info "Resources will be automatically cleaned up at the end"
    echo ""
    
    # Create security violations
    result=$(create_security_violations)
    IFS=',' read -r bucket_name sg_id iam_user access_key <<< "$result"
    
    # Monitor for findings
    monitor_securityhub_findings "$bucket_name" "$sg_id" "$iam_user" "$MONITORING_DURATION"
    
    # Generate report
    generate_demo_report "$bucket_name" "$sg_id" "$iam_user" "$access_key"
    
    log_success "🎯 Security Hub Demo completed!"
    log_info "💡 Check the AWS Security Hub console for findings"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi