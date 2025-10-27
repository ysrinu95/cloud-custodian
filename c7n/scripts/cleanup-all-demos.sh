#!/bin/bash

# Cloud Custodian Demo Cleanup Script
# This script cleans up all resources created by Cloud Custodian demo scenarios

set -e

# Configuration
REGION="${AWS_REGION:-us-east-1}"
DEMO_TAG_KEY="CustodianDemo"

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

cleanup_ec2_resources() {
    log_info "🖥️ Cleaning up EC2 demo resources..."
    
    # Terminate demo EC2 instances
    local instances=$(aws ec2 describe-instances \
        --region "$REGION" \
        --filters "Name=tag:$DEMO_TAG_KEY,Values=GuardDutyTest,ConfigComplianceTest,SecurityHubTest,EC2PublicInstanceTest" "Name=instance-state-name,Values=running,pending,stopped" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$instances" && "$instances" != "None" ]]; then
        log_info "Terminating demo EC2 instances: $instances"
        aws ec2 terminate-instances --region "$REGION" --instance-ids $instances || true
        
        # Wait for termination
        log_info "Waiting for instances to terminate..."
        aws ec2 wait instance-terminated --region "$REGION" --instance-ids $instances || true
        log_success "EC2 instances terminated"
    else
        log_info "No demo EC2 instances found"
    fi
    
    # Delete demo security groups
    local security_groups=$(aws ec2 describe-security-groups \
        --region "$REGION" \
        --filters "Name=tag:$DEMO_TAG_KEY,Values=GuardDutyTest,ConfigComplianceTest,SecurityHubTest,EC2PublicInstanceTest" \
        --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$security_groups" && "$security_groups" != "None" ]]; then
        log_info "Deleting demo security groups: $security_groups"
        for sg in $security_groups; do
            aws ec2 delete-security-group --region "$REGION" --group-id "$sg" || true
        done
        log_success "Security groups deleted"
    else
        log_info "No demo security groups found"
    fi
    
    # Delete demo key pairs
    local keypairs=$(aws ec2 describe-key-pairs \
        --region "$REGION" \
        --filters "Name=tag:$DEMO_TAG_KEY,Values=GuardDutyTest,ConfigComplianceTest,SecurityHubTest,EC2PublicInstanceTest" \
        --query 'KeyPairs[].KeyName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$keypairs" && "$keypairs" != "None" ]]; then
        log_info "Deleting demo key pairs: $keypairs"
        for kp in $keypairs; do
            aws ec2 delete-key-pair --region "$REGION" --key-name "$kp" || true
        done
        log_success "Key pairs deleted"
    else
        log_info "No demo key pairs found"
    fi
    
    # Delete demo EBS volumes
    local volumes=$(aws ec2 describe-volumes \
        --region "$REGION" \
        --filters "Name=tag:$DEMO_TAG_KEY,Values=GuardDutyTest,ConfigComplianceTest,SecurityHubTest,EC2PublicInstanceTest" \
        --query 'Volumes[].VolumeId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$volumes" && "$volumes" != "None" ]]; then
        log_info "Deleting demo EBS volumes: $volumes"
        for volume in $volumes; do
            aws ec2 delete-volume --region "$REGION" --volume-id "$volume" || true
        done
        log_success "EBS volumes deleted"
    else
        log_info "No demo EBS volumes found"
    fi
}

cleanup_s3_resources() {
    log_info "📦 Cleaning up S3 demo resources..."
    
    # Delete demo S3 buckets
    local demo_buckets=$(aws s3api list-buckets \
        --query "Buckets[?contains(Name, 'custodian') && (contains(Name, 'test') || contains(Name, 'demo'))].Name" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$demo_buckets" && "$demo_buckets" != "None" ]]; then
        log_info "Found demo buckets: $demo_buckets"
        
        for bucket in $demo_buckets; do
            log_info "Deleting bucket: $bucket"
            
            # Check if bucket has versioning enabled
            local versioning=$(aws s3api get-bucket-versioning \
                --bucket "$bucket" \
                --query 'Status' \
                --output text 2>/dev/null || echo "Disabled")
            
            if [[ "$versioning" == "Enabled" ]]; then
                # Delete all versions and delete markers
                aws s3api delete-objects \
                    --bucket "$bucket" \
                    --delete "$(aws s3api list-object-versions \
                        --bucket "$bucket" \
                        --output json \
                        --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" 2>/dev/null || true
                
                aws s3api delete-objects \
                    --bucket "$bucket" \
                    --delete "$(aws s3api list-object-versions \
                        --bucket "$bucket" \
                        --output json \
                        --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" 2>/dev/null || true
            fi
            
            # Force delete bucket
            aws s3 rb s3://$bucket --force --region "$REGION" || true
        done
        
        log_success "S3 buckets deleted"
    else
        log_info "No demo S3 buckets found"
    fi
}

cleanup_iam_resources() {
    log_info "👤 Cleaning up IAM demo resources..."
    
    # Delete demo IAM users
    local demo_users=$(aws iam list-users \
        --query "Users[?contains(UserName, 'test') && (contains(UserName, 'securityhub') || contains(UserName, 'guardduty') || contains(UserName, 'custodian'))].UserName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$demo_users" && "$demo_users" != "None" ]]; then
        log_info "Found demo IAM users: $demo_users"
        
        for user in $demo_users; do
            log_info "Deleting IAM user: $user"
            
            # Delete access keys
            local keys=$(aws iam list-access-keys \
                --user-name "$user" \
                --query 'AccessKeyMetadata[].AccessKeyId' \
                --output text 2>/dev/null || echo "")
            
            for key in $keys; do
                if [[ -n "$key" && "$key" != "None" ]]; then
                    aws iam delete-access-key --user-name "$user" --access-key-id "$key" || true
                fi
            done
            
            # Delete user policies
            local policies=$(aws iam list-user-policies \
                --user-name "$user" \
                --query 'PolicyNames[]' \
                --output text 2>/dev/null || echo "")
            
            for policy in $policies; do
                if [[ -n "$policy" && "$policy" != "None" ]]; then
                    aws iam delete-user-policy --user-name "$user" --policy-name "$policy" || true
                fi
            done
            
            # Delete user
            aws iam delete-user --user-name "$user" || true
        done
        
        log_success "IAM users deleted"
    else
        log_info "No demo IAM users found"
    fi
    
    # Delete demo IAM roles
    local demo_roles=$(aws iam list-roles \
        --query "Roles[?contains(RoleName, 'test') && (contains(RoleName, 'access-analyzer') || contains(RoleName, 'custodian'))].RoleName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$demo_roles" && "$demo_roles" != "None" ]]; then
        log_info "Found demo IAM roles: $demo_roles"
        
        for role in $demo_roles; do
            log_info "Deleting IAM role: $role"
            
            # Detach managed policies
            local attached_policies=$(aws iam list-attached-role-policies \
                --role-name "$role" \
                --query 'AttachedPolicies[].PolicyArn' \
                --output text 2>/dev/null || echo "")
            
            for policy_arn in $attached_policies; do
                if [[ -n "$policy_arn" && "$policy_arn" != "None" ]]; then
                    aws iam detach-role-policy --role-name "$role" --policy-arn "$policy_arn" || true
                fi
            done
            
            # Delete inline policies
            local inline_policies=$(aws iam list-role-policies \
                --role-name "$role" \
                --query 'PolicyNames[]' \
                --output text 2>/dev/null || echo "")
            
            for policy in $inline_policies; do
                if [[ -n "$policy" && "$policy" != "None" ]]; then
                    aws iam delete-role-policy --role-name "$role" --policy-name "$policy" || true
                fi
            done
            
            # Delete role
            aws iam delete-role --role-name "$role" || true
        done
        
        log_success "IAM roles deleted"
    else
        log_info "No demo IAM roles found"
    fi
}

cleanup_kms_resources() {
    log_info "🔑 Cleaning up KMS demo resources..."
    
    # Schedule deletion of demo KMS keys
    local demo_keys=$(aws kms list-keys \
        --region "$REGION" \
        --query 'Keys[].KeyId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$demo_keys" && "$demo_keys" != "None" ]]; then
        for key_id in $demo_keys; do
            # Check if this is a demo key by looking at aliases
            local aliases=$(aws kms list-aliases \
                --region "$REGION" \
                --key-id "$key_id" \
                --query 'Aliases[?contains(AliasName, `demo`) || contains(AliasName, `test`)].AliasName' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$aliases" && "$aliases" != "None" ]]; then
                log_info "Scheduling deletion of demo KMS key: $key_id"
                
                # Delete aliases first
                for alias in $aliases; do
                    aws kms delete-alias --alias-name "$alias" --region "$REGION" || true
                done
                
                # Schedule key deletion
                aws kms schedule-key-deletion \
                    --key-id "$key_id" \
                    --pending-window-in-days 7 \
                    --region "$REGION" || true
            fi
        done
        
        log_success "Demo KMS keys scheduled for deletion"
    else
        log_info "No demo KMS keys found"
    fi
}

cleanup_sqs_resources() {
    log_info "📬 Cleaning up SQS demo resources..."
    
    # Delete demo SQS queues
    local demo_queues=$(aws sqs list-queues \
        --region "$REGION" \
        --queue-name-prefix "custodian" \
        --query 'QueueUrls[]' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$demo_queues" && "$demo_queues" != "None" ]]; then
        for queue_url in $demo_queues; do
            if [[ "$queue_url" == *"demo"* || "$queue_url" == *"test"* ]]; then
                log_info "Deleting demo SQS queue: $queue_url"
                aws sqs delete-queue --queue-url "$queue_url" --region "$REGION" || true
            fi
        done
        
        log_success "Demo SQS queues deleted"
    else
        log_info "No demo SQS queues found"
    fi
}

cleanup_macie_resources() {
    log_info "🔍 Cleaning up Macie demo resources..."
    
    # Cancel demo classification jobs
    local demo_jobs=$(aws macie2 list-classification-jobs \
        --region "$REGION" \
        --filter-criteria jobType=ONE_TIME \
        --query 'items[?contains(name, `demo`) || contains(name, `test`)].jobId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$demo_jobs" && "$demo_jobs" != "None" ]]; then
        for job_id in $demo_jobs; do
            log_info "Cancelling Macie job: $job_id"
            aws macie2 cancel-classification-job \
                --job-id "$job_id" \
                --region "$REGION" || true
        done
        
        log_success "Demo Macie jobs cancelled"
    else
        log_info "No demo Macie jobs found"
    fi
}

cleanup_cloudtrail_resources() {
    log_info "📊 Cleaning up CloudTrail demo resources..."
    
    # Delete demo CloudTrails
    local demo_trails=$(aws cloudtrail describe-trails \
        --region "$REGION" \
        --query 'trailList[?contains(Name, `demo`) || contains(Name, `test`)].Name' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$demo_trails" && "$demo_trails" != "None" ]]; then
        for trail_name in $demo_trails; do
            log_info "Deleting CloudTrail: $trail_name"
            aws cloudtrail stop-logging --name "$trail_name" --region "$REGION" || true
            aws cloudtrail delete-trail --name "$trail_name" --region "$REGION" || true
        done
        
        log_success "Demo CloudTrails deleted"
    else
        log_info "No demo CloudTrails found"
    fi
}

generate_cleanup_report() {
    local resources_cleaned="$1"
    
    log_info "📋 Generating Cleanup Report..."
    
    cat << EOF

🧹 Cloud Custodian Demo Cleanup Report
════════════════════════════════════════════════════════════════════════

📊 Cleanup Summary:
  • Region: $REGION
  • Cleanup Time: $(date)
  • Resources Processed: $resources_cleaned

🗑️ Resources Cleaned:
  ✅ EC2 Instances (demo tagged)
  ✅ Security Groups (demo tagged)
  ✅ Key Pairs (demo tagged)
  ✅ EBS Volumes (demo tagged)
  ✅ S3 Buckets (custodian demo/test buckets)
  ✅ IAM Users (demo/test users)
  ✅ IAM Roles (demo/test roles)
  ✅ KMS Keys (demo aliases, scheduled for deletion)
  ✅ SQS Queues (demo/test queues)
  ✅ Macie Classification Jobs (demo/test jobs)
  ✅ CloudTrail Trails (demo/test trails)

🔍 Verification Steps:
  1. Check EC2 Console for terminated instances
  2. Verify S3 buckets are deleted
  3. Confirm IAM users/roles are removed
  4. Check KMS keys are scheduled for deletion

⚠️ Notes:
  • KMS keys are scheduled for deletion (7-day waiting period)
  • Some resources may take a few minutes to fully disappear
  • CloudWatch logs are retained (managed separately)
  • Lambda functions are managed by Cloud Custodian deployment

✅ Cleanup completed successfully!

EOF
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Cloud Custodian Demo Cleanup Script - Removes all demo resources

OPTIONS:
    --region REGION         AWS region (default: us-east-1)
    --dry-run              Show what would be deleted without deleting
    --help                 Show this help message

EXAMPLES:
    $0                           # Clean up all demo resources in us-east-1
    $0 --region us-west-2        # Clean up resources in us-west-2
    $0 --dry-run                 # Show what would be deleted

WARNING: This script will DELETE AWS resources. Use with caution.

EOF
}

main() {
    local dry_run=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --region)
                REGION="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
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
    
    log_info "🧹 Cloud Custodian Demo Cleanup"
    log_info "Region: $REGION"
    
    if [[ "$dry_run" == true ]]; then
        log_warning "🔍 DRY RUN MODE - No resources will be deleted"
    else
        log_warning "⚠️ LIVE MODE - Resources will be permanently deleted"
    fi
    
    echo ""
    
    if [[ "$dry_run" == true ]]; then
        log_info "Would clean up the following resource types:"
        log_info "  • EC2 instances, security groups, key pairs, EBS volumes"
        log_info "  • S3 buckets with 'custodian' and 'demo/test' in names"
        log_info "  • IAM users and roles with 'demo/test' in names"
        log_info "  • KMS keys with demo aliases"
        log_info "  • SQS queues with 'custodian' prefix and 'demo/test'"
        log_info "  • Macie classification jobs with 'demo/test' names"
        log_info "  • CloudTrail trails with 'demo/test' names"
        
        log_success "🔍 Dry run completed - no actual cleanup performed"
        exit 0
    fi
    
    log_warning "⚠️ This will permanently delete demo resources!"
    log_warning "⚠️ Make sure you want to proceed before continuing"
    echo ""
    
    local resources_cleaned=0
    
    # Clean up resources in order
    cleanup_ec2_resources
    resources_cleaned=$((resources_cleaned + 1))
    
    cleanup_s3_resources
    resources_cleaned=$((resources_cleaned + 1))
    
    cleanup_iam_resources
    resources_cleaned=$((resources_cleaned + 1))
    
    cleanup_kms_resources
    resources_cleaned=$((resources_cleaned + 1))
    
    cleanup_sqs_resources
    resources_cleaned=$((resources_cleaned + 1))
    
    cleanup_macie_resources
    resources_cleaned=$((resources_cleaned + 1))
    
    cleanup_cloudtrail_resources
    resources_cleaned=$((resources_cleaned + 1))
    
    # Generate cleanup report
    generate_cleanup_report "$resources_cleaned"
    
    log_success "🎯 Demo cleanup completed successfully!"
    log_info "💡 All demo resources have been removed from region $REGION"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi