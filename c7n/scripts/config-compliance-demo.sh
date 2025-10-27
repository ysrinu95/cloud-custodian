#!/bin/bash

# Cloud Custodian Config Compliance Demo
# This script creates real compliance violations that AWS Config will detect

set -e

# Configuration
REGION="${AWS_REGION:-us-east-1}"
DEMO_PREFIX="custodian-config-demo"
DEMO_TAG_KEY="CustodianDemo"
DEMO_TAG_VALUE="ConfigComplianceTest"
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
    log_info "🧹 Cleaning up Config demo resources..."
    
    # Delete demo S3 buckets
    local buckets=$(aws s3api list-buckets \
        --query "Buckets[?contains(Name, 'custodian-config-test') || contains(Name, 'config-demo-bucket')].Name" \
        --output text 2>/dev/null || echo "")
    
    for bucket in $buckets; do
        if [[ -n "$bucket" && "$bucket" != "None" ]]; then
            log_info "Deleting bucket: $bucket"
            aws s3 rb s3://$bucket --force --region "$REGION" || true
        fi
    done
    
    # Delete demo EBS volumes
    local volumes=$(aws ec2 describe-volumes \
        --region "$REGION" \
        --filters "Name=tag:$DEMO_TAG_KEY,Values=$DEMO_TAG_VALUE" \
        --query 'Volumes[].VolumeId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$volumes" && "$volumes" != "None" ]]; then
        log_info "Deleting EBS volumes: $volumes"
        for volume in $volumes; do
            aws ec2 delete-volume --region "$REGION" --volume-id "$volume" || true
        done
    fi
    
    log_success "Config demo cleanup completed"
}

check_config_status() {
    log_info "🔍 Checking AWS Config status..."
    
    # Check if Config is enabled
    local recorders=$(aws configservice describe-configuration-recorders \
        --region "$REGION" \
        --query 'ConfigurationRecorders[0].name' \
        --output text 2>/dev/null || echo "None")
    
    if [[ "$recorders" == "None" || -z "$recorders" ]]; then
        log_warning "AWS Config is not configured in region $REGION"
        log_info "Setting up AWS Config for demo..."
        
        # Create Config bucket
        local config_bucket="aws-config-bucket-${REGION}-$(date +%s)"
        aws s3 mb s3://$config_bucket --region "$REGION"
        
        # Create Config service role
        cat > /tmp/config-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "config.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
        
        aws iam create-role \
            --role-name aws-config-role \
            --assume-role-policy-document file:///tmp/config-trust-policy.json \
            --region "$REGION" || true
        
        aws iam attach-role-policy \
            --role-name aws-config-role \
            --policy-arn arn:aws:iam::aws:policy/service-role/ConfigRole \
            --region "$REGION" || true
        
        sleep 10
        
        local account_id=$(aws sts get-caller-identity --query Account --output text)
        
        # Create configuration recorder
        aws configservice put-configuration-recorder \
            --configuration-recorder name=default,roleARN=arn:aws:iam::${account_id}:role/aws-config-role \
            --recording-group allSupported=true,includeGlobalResourceTypes=true \
            --region "$REGION"
        
        # Create delivery channel
        aws configservice put-delivery-channel \
            --delivery-channel name=default,s3BucketName=$config_bucket \
            --region "$REGION"
        
        # Start recording
        aws configservice start-configuration-recorder \
            --configuration-recorder-name default \
            --region "$REGION"
        
        log_success "AWS Config configured with bucket: $config_bucket"
        
        rm -f /tmp/config-trust-policy.json
    else
        log_success "AWS Config recorder found: $recorders"
    fi
}

create_compliance_violations() {
    log_info "🚀 Creating real compliance violations for Config to detect..."
    
    # Violation 1: Create public S3 bucket
    local bucket_name="custodian-config-test-public-$(date +%s)"
    
    log_info "📦 Creating non-compliant S3 bucket..."
    aws s3 mb s3://$bucket_name --region "$REGION"
    
    # Make bucket public (violates s3-bucket-public-read-prohibited)
    log_warning "🔓 Making bucket public (Config violation)..."
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
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::$bucket_name/*"
    }
  ]
}
EOF
    
    aws s3api put-bucket-policy \
        --bucket "$bucket_name" \
        --policy file:///tmp/public-bucket-policy.json \
        --region "$REGION"
    
    log_success "Created public S3 bucket: $bucket_name"
    
    # Violation 2: Create unencrypted EBS volume
    log_info "💾 Creating unencrypted EBS volume..."
    
    local az=$(aws ec2 describe-availability-zones \
        --region "$REGION" \
        --query 'AvailabilityZones[0].ZoneName' \
        --output text)
    
    local volume_id=$(aws ec2 create-volume \
        --region "$REGION" \
        --availability-zone "$az" \
        --size 8 \
        --volume-type gp3 \
        --tag-specifications "ResourceType=volume,Tags=[{Key=$DEMO_TAG_KEY,Value=$DEMO_TAG_VALUE},{Key=Name,Value=$DEMO_PREFIX-unencrypted}]" \
        --query 'VolumeId' \
        --output text)
    
    log_success "Created unencrypted EBS volume: $volume_id"
    
    # Violation 3: Create security group with overly permissive rules
    log_info "🌐 Creating non-compliant security group..."
    
    local vpc_id=$(aws ec2 describe-vpcs \
        --region "$REGION" \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' \
        --output text)
    
    if [[ "$vpc_id" != "None" && -n "$vpc_id" ]]; then
        local sg_id=$(aws ec2 create-security-group \
            --region "$REGION" \
            --group-name "$DEMO_PREFIX-non-compliant-sg" \
            --description "Non-compliant security group for Config demo" \
            --vpc-id "$vpc_id" \
            --tag-specifications "ResourceType=security-group,Tags=[{Key=$DEMO_TAG_KEY,Value=$DEMO_TAG_VALUE}]" \
            --query 'GroupId' \
            --output text)
        
        # Add SSH access from everywhere (violates security best practices)
        aws ec2 authorize-security-group-ingress \
            --region "$REGION" \
            --group-id "$sg_id" \
            --protocol tcp \
            --port 22 \
            --cidr 0.0.0.0/0
        
        log_success "Created non-compliant security group: $sg_id"
    fi
    
    rm -f /tmp/public-bucket-policy.json
    
    echo "$bucket_name,$volume_id,$sg_id"
}

setup_config_rules() {
    log_info "🔧 Setting up Config rules for compliance testing..."
    
    # Rule 1: S3 bucket public read prohibited
    local rule_name="s3-bucket-public-read-prohibited"
    
    if ! aws configservice describe-config-rules \
        --config-rule-names "$rule_name" \
        --region "$REGION" >/dev/null 2>&1; then
        
        aws configservice put-config-rule \
            --config-rule '{
                "ConfigRuleName": "'$rule_name'",
                "Description": "Checks that S3 buckets do not allow public read access",
                "Source": {
                    "Owner": "AWS",
                    "SourceIdentifier": "S3_BUCKET_PUBLIC_READ_PROHIBITED"
                }
            }' \
            --region "$REGION"
        
        log_success "Created Config rule: $rule_name"
    fi
    
    # Rule 2: EBS encryption enabled
    local ebs_rule="encrypted-volumes"
    
    if ! aws configservice describe-config-rules \
        --config-rule-names "$ebs_rule" \
        --region "$REGION" >/dev/null 2>&1; then
        
        aws configservice put-config-rule \
            --config-rule '{
                "ConfigRuleName": "'$ebs_rule'",
                "Description": "Checks that EBS volumes are encrypted",
                "Source": {
                    "Owner": "AWS", 
                    "SourceIdentifier": "ENCRYPTED_VOLUMES"
                }
            }' \
            --region "$REGION"
        
        log_success "Created Config rule: $ebs_rule"
    fi
}

monitor_config_compliance() {
    local bucket_name="$1"
    local volume_id="$2" 
    local duration="$3"
    
    log_info "📊 Monitoring Config compliance for $duration minutes..."
    
    local end_time=$(($(date +%s) + duration * 60))
    local check_count=0
    
    while [[ $(date +%s) -lt $end_time ]]; do
        check_count=$((check_count + 1))
        
        log_info "Check #$check_count - Looking for compliance violations..."
        
        # Trigger manual evaluation
        aws configservice start-config-rules-evaluation \
            --config-rule-names s3-bucket-public-read-prohibited encrypted-volumes \
            --region "$REGION" || true
        
        # Check compliance status
        local violations=$(aws configservice get-compliance-details-by-config-rule \
            --config-rule-name s3-bucket-public-read-prohibited \
            --region "$REGION" \
            --query 'EvaluationResults[?ComplianceType==`NON_COMPLIANT`].EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$violations" && "$violations" != "None" ]]; then
            log_success "🚨 Found Config compliance violations!"
            
            # Show violation details
            aws configservice get-compliance-details-by-config-rule \
                --config-rule-name s3-bucket-public-read-prohibited \
                --region "$REGION" \
                --query 'EvaluationResults[?ComplianceType==`NON_COMPLIANT`].[EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId,ComplianceType,ResultRecordedTime]' \
                --output table
            
            break
        else
            log_info "No violations detected yet... (Config needs time to evaluate)"
        fi
        
        sleep 60
    done
}

generate_demo_report() {
    local bucket_name="$1"
    local volume_id="$2"
    local sg_id="$3"
    
    log_info "📋 Generating Config Compliance Demo Report..."
    
    cat << EOF

📋 Config Compliance Demo Report
════════════════════════════════════════════════════════════════════════

📊 Demo Summary:
  • Region: $REGION
  • Demo Duration: $MONITORING_DURATION minutes
  • Demo Resources Created: 3

🚨 Compliance Violations Created:
  • S3 bucket with public read access: $bucket_name
  • Unencrypted EBS volume: $volume_id
  • Security group with overly permissive rules: $sg_id

⚠️ Expected Config Rule Violations:
  • S3_BUCKET_PUBLIC_READ_PROHIBITED
  • ENCRYPTED_VOLUMES
  • EC2_SECURITY_GROUP_ATTACHED_TO_ENI

🔍 Next Steps:
  1. Check AWS Config console for compliance violations
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

Config Compliance Demo Script - Creates non-compliant AWS resources for Config testing

OPTIONS:
    --region REGION         AWS region (default: us-east-1)
    --duration MINUTES      Monitoring duration in minutes (default: 15)
    --cleanup              Clean up demo resources and exit
    --check-only           Only check Config status
    --help                 Show this help message

EXAMPLES:
    $0                           # Run full demo with defaults
    $0 --region us-west-2        # Run demo in us-west-2
    $0 --duration 30             # Monitor for 30 minutes
    $0 --cleanup                 # Clean up all demo resources
    $0 --check-only              # Just check Config status

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
    
    log_info "📋 Cloud Custodian Config Compliance Demo"
    log_info "Region: $REGION"
    log_info "Monitoring Duration: $MONITORING_DURATION minutes"
    echo ""
    
    # Cleanup mode
    if [[ "$cleanup_only" == true ]]; then
        cleanup_resources
        log_success "🧹 Cleanup completed"
        exit 0
    fi
    
    # Check Config status
    check_config_status
    
    if [[ "$check_only" == true ]]; then
        log_success "✅ Config check completed"
        exit 0
    fi
    
    # Trap to cleanup on exit
    trap cleanup_resources EXIT
    
    log_warning "⚠️ WARNING: This demo will create non-compliant AWS resources!"
    log_warning "⚠️ These resources will be flagged by AWS Config as non-compliant"
    log_info "Resources will be automatically cleaned up at the end"
    echo ""
    
    # Set up Config rules
    setup_config_rules
    
    # Create compliance violations
    result=$(create_compliance_violations)
    IFS=',' read -r bucket_name volume_id sg_id <<< "$result"
    
    # Monitor for compliance violations
    monitor_config_compliance "$bucket_name" "$volume_id" "$MONITORING_DURATION"
    
    # Generate report
    generate_demo_report "$bucket_name" "$volume_id" "$sg_id"
    
    log_success "🎯 Config Compliance Demo completed!"
    log_info "💡 Check the AWS Config console for compliance violations"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi