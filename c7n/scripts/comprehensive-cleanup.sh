#!/bin/bash
# Comprehensive Cloud Custodian Demo Resource Cleanup Script
# Removes ALL resources created by security findings tests and other demos

set -e

REGION="${AWS_REGION:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

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

log_cleanup() {
    echo -e "${PURPLE}🗑️ $1${NC}"
}

# Confirmation function
confirm_cleanup() {
    local cleanup_type="$1"
    echo "═══════════════════════════════════════════════════════════"
    echo "🚨 CLEANUP CONFIRMATION"
    echo "═══════════════════════════════════════════════════════════"
    echo "Type: $cleanup_type"
    echo "Region: $REGION"
    echo "Account: $(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo 'Unknown')"
    echo ""
    echo "This will permanently delete resources and cannot be undone!"
    echo ""
    read -p "Type 'DELETE' to confirm: " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log_warning "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    log_info "Cleanup confirmed. Starting in 3 seconds..."
    sleep 3
}

# Security test resources cleanup
cleanup_security_tests() {
    log_info "Phase 1: Security Test Resources Cleanup"
    echo "─────────────────────────────────────────────────"
    
    # 1. S3 buckets from security tests
    log_cleanup "Removing security test S3 buckets..."
    BUCKET_COUNT=0
    aws s3 ls | grep -E "(custodian-test|custodian-macie|custodian-s3-logs|custodian-suspicious)" | while read -r line; do
        bucket=$(echo $line | awk '{print $3}')
        if [[ -n "$bucket" ]]; then
            echo "  🗑️ Bucket: $bucket"
            # Force empty and delete
            aws s3 rm s3://$bucket --recursive --region ${REGION} 2>/dev/null || true
            aws s3 rb s3://$bucket --force --region ${REGION} 2>/dev/null || true
            BUCKET_COUNT=$((BUCKET_COUNT + 1))
        fi
    done
    log_success "Security test S3 buckets processed"
    
    # 2. IAM users from security tests
    log_cleanup "Removing security test IAM users..."
    USER_COUNT=0
    aws iam list-users --query 'Users[?starts_with(UserName, `custodian-test-user`)].UserName' --output text | while read -r user; do
        if [[ -n "$user" ]] && [[ "$user" != "None" ]]; then
            echo "  🗑️ IAM User: $user"
            
            # Remove access keys
            aws iam list-access-keys --user-name "$user" --query 'AccessKeyMetadata[].AccessKeyId' --output text | while read -r key; do
                if [[ -n "$key" ]] && [[ "$key" != "None" ]]; then
                    aws iam delete-access-key --user-name "$user" --access-key-id "$key" 2>/dev/null || true
                fi
            done
            
            # Remove user policies
            aws iam list-user-policies --user-name "$user" --query 'PolicyNames[]' --output text | while read -r policy; do
                if [[ -n "$policy" ]] && [[ "$policy" != "None" ]]; then
                    aws iam delete-user-policy --user-name "$user" --policy-name "$policy" 2>/dev/null || true
                fi
            done
            
            # Remove attached policies
            aws iam list-attached-user-policies --user-name "$user" --query 'AttachedPolicies[].PolicyArn' --output text | while read -r arn; do
                if [[ -n "$arn" ]] && [[ "$arn" != "None" ]]; then
                    aws iam detach-user-policy --user-name "$user" --policy-arn "$arn" 2>/dev/null || true
                fi
            done
            
            # Delete user
            aws iam delete-user --user-name "$user" 2>/dev/null || true
            USER_COUNT=$((USER_COUNT + 1))
        fi
    done
    log_success "Security test IAM users processed"
    
    # 3. IAM roles from security tests
    log_cleanup "Removing security test IAM roles..."
    ROLE_COUNT=0
    aws iam list-roles --query 'Roles[?starts_with(RoleName, `CustodianTestRole`)].RoleName' --output text | while read -r role; do
        if [[ -n "$role" ]] && [[ "$role" != "None" ]]; then
            echo "  🗑️ IAM Role: $role"
            
            # Remove attached policies
            aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text | while read -r arn; do
                if [[ -n "$arn" ]] && [[ "$arn" != "None" ]]; then
                    aws iam detach-role-policy --role-name "$role" --policy-arn "$arn" 2>/dev/null || true
                fi
            done
            
            # Remove inline policies
            aws iam list-role-policies --role-name "$role" --query 'PolicyNames[]' --output text | while read -r policy; do
                if [[ -n "$policy" ]] && [[ "$policy" != "None" ]]; then
                    aws iam delete-role-policy --role-name "$role" --policy-name "$policy" 2>/dev/null || true
                fi
            done
            
            # Delete role
            aws iam delete-role --role-name "$role" 2>/dev/null || true
            ROLE_COUNT=$((ROLE_COUNT + 1))
        fi
    done
    log_success "Security test IAM roles processed"
    
    # 4. Security Hub test findings
    log_cleanup "Archiving Security Hub test findings..."
    FINDINGS_COUNT=0
    TEST_FINDINGS=$(aws securityhub get-findings \
        --filters '{"Title": [{"Value": "[TEST]", "Comparison": "PREFIX"}], "Title": [{"Value": "[DEMO]", "Comparison": "PREFIX"}]}' \
        --query 'Findings[].Id' \
        --output text \
        --region ${REGION} 2>/dev/null || echo "")
    
    if [[ -n "$TEST_FINDINGS" ]] && [[ "$TEST_FINDINGS" != "None" ]]; then
        echo "$TEST_FINDINGS" | while read -r finding_id; do
            if [[ -n "$finding_id" ]]; then
                echo "  🗑️ Finding: $finding_id"
                aws securityhub batch-update-findings \
                    --finding-identifiers Id="$finding_id",ProductArn="arn:aws:securityhub:${REGION}:$(aws sts get-caller-identity --query Account --output text):product/aws/securityhub" \
                    --workflow Status=RESOLVED,ReasonCode=TEST_COMPLETED \
                    --region ${REGION} 2>/dev/null || true
                FINDINGS_COUNT=$((FINDINGS_COUNT + 1))
            fi
        done
    fi
    log_success "Security Hub test findings processed"
}

# EC2/RDS/EBS demo resources cleanup
cleanup_demo_resources() {
    log_info "Phase 2: EC2/RDS/EBS Demo Resources Cleanup"
    echo "─────────────────────────────────────────────────"
    
    # 1. EC2 instances
    log_cleanup "Terminating demo EC2 instances..."
    INSTANCE_COUNT=0
    
    # Instances with TestResource tag
    aws ec2 describe-instances --filters "Name=tag:TestResource,Values=true" --query 'Reservations[].Instances[?State.Name!=`terminated`].[InstanceId,State.Name,Tags[?Key==`Name`].Value|[0]]' --output text --region ${REGION} | while read -r instance_id state name; do
        if [[ -n "$instance_id" ]] && [[ "$instance_id" != "None" ]]; then
            echo "  🗑️ Instance: $instance_id ($name) [$state]"
            aws ec2 terminate-instances --instance-ids "$instance_id" --region ${REGION} 2>/dev/null || true
            INSTANCE_COUNT=$((INSTANCE_COUNT + 1))
        fi
    done
    
    # Instances with demo naming patterns
    aws ec2 describe-instances --filters "Name=tag:Name,Values=*demo*,*test*,*custodian*" --query 'Reservations[].Instances[?State.Name!=`terminated`].[InstanceId,State.Name,Tags[?Key==`Name`].Value|[0]]' --output text --region ${REGION} | while read -r instance_id state name; do
        if [[ -n "$instance_id" ]] && [[ "$instance_id" != "None" ]]; then
            echo "  🗑️ Demo Instance: $instance_id ($name) [$state]"
            aws ec2 terminate-instances --instance-ids "$instance_id" --region ${REGION} 2>/dev/null || true
            INSTANCE_COUNT=$((INSTANCE_COUNT + 1))
        fi
    done
    log_success "Demo EC2 instances processed"
    
    # 2. EBS volumes and snapshots
    log_cleanup "Removing demo EBS volumes and snapshots..."
    
    # Available volumes with demo tags
    aws ec2 describe-volumes --filters "Name=tag:TestResource,Values=true" "Name=state,Values=available" --query 'Volumes[].VolumeId' --output text --region ${REGION} | while read -r volume_id; do
        if [[ -n "$volume_id" ]] && [[ "$volume_id" != "None" ]]; then
            echo "  🗑️ Volume: $volume_id"
            aws ec2 delete-volume --volume-id "$volume_id" --region ${REGION} 2>/dev/null || true
        fi
    done
    
    # Demo snapshots
    aws ec2 describe-snapshots --owner-ids self --query 'Snapshots[?contains(Description, `demo`) || contains(Description, `test`) || contains(Description, `custodian`)].SnapshotId' --output text --region ${REGION} | while read -r snapshot_id; do
        if [[ -n "$snapshot_id" ]] && [[ "$snapshot_id" != "None" ]]; then
            echo "  🗑️ Snapshot: $snapshot_id"
            aws ec2 delete-snapshot --snapshot-id "$snapshot_id" --region ${REGION} 2>/dev/null || true
        fi
    done
    log_success "Demo EBS resources processed"
    
    # 3. RDS instances
    log_cleanup "Removing demo RDS instances..."
    aws rds describe-db-instances --query 'DBInstances[?contains(DBInstanceIdentifier, `demo`) || contains(DBInstanceIdentifier, `test`) || contains(DBInstanceIdentifier, `custodian`)].DBInstanceIdentifier' --output text --region ${REGION} | while read -r db_id; do
        if [[ -n "$db_id" ]] && [[ "$db_id" != "None" ]]; then
            echo "  🗑️ RDS Instance: $db_id"
            aws rds delete-db-instance --db-instance-identifier "$db_id" --skip-final-snapshot --region ${REGION} 2>/dev/null || true
        fi
    done
    log_success "Demo RDS instances processed"
    
    # 4. Security groups
    log_cleanup "Removing demo security groups..."
    aws ec2 describe-security-groups --filters "Name=group-name,Values=*demo*,*test*,*custodian*" --query 'SecurityGroups[?GroupName!=`default`].[GroupId,GroupName]' --output text --region ${REGION} | while read -r sg_id sg_name; do
        if [[ -n "$sg_id" ]] && [[ "$sg_id" != "None" ]]; then
            echo "  🗑️ Security Group: $sg_id ($sg_name)"
            aws ec2 delete-security-group --group-id "$sg_id" --region ${REGION} 2>/dev/null || true
        fi
    done
    log_success "Demo security groups processed"
    
    # 5. Key pairs
    log_cleanup "Removing demo key pairs..."
    aws ec2 describe-key-pairs --query 'KeyPairs[?contains(KeyName, `demo`) || contains(KeyName, `test`) || contains(KeyName, `custodian`)].KeyName' --output text --region ${REGION} | while read -r key_name; do
        if [[ -n "$key_name" ]] && [[ "$key_name" != "None" ]]; then
            echo "  🗑️ Key Pair: $key_name"
            aws ec2 delete-key-pair --key-name "$key_name" --region ${REGION} 2>/dev/null || true
        fi
    done
    log_success "Demo key pairs processed"
    
    # 6. S3 buckets (non-security test buckets)
    log_cleanup "Removing remaining demo S3 buckets..."
    aws s3 ls | grep -E "(demo|test|sample)" | grep -v -E "(custodian-test|custodian-macie|custodian-s3-logs)" | while read -r line; do
        bucket=$(echo $line | awk '{print $3}')
        if [[ -n "$bucket" ]]; then
            echo "  🗑️ S3 Bucket: $bucket"
            aws s3 rm s3://$bucket --recursive --region ${REGION} 2>/dev/null || true
            aws s3 rb s3://$bucket --force --region ${REGION} 2>/dev/null || true
        fi
    done
    log_success "Demo S3 buckets processed"
}

# CloudFormation and advanced cleanup
cleanup_advanced_resources() {
    log_info "Phase 3: Advanced Resources Cleanup"
    echo "─────────────────────────────────────────────────"
    
    # 1. CloudFormation stacks
    log_cleanup "Removing demo CloudFormation stacks..."
    aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query 'StackSummaries[?contains(StackName, `demo`) || contains(StackName, `test`) || contains(StackName, `custodian`)].StackName' --output text --region ${REGION} | while read -r stack_name; do
        if [[ -n "$stack_name" ]] && [[ "$stack_name" != "None" ]]; then
            echo "  🗑️ CloudFormation Stack: $stack_name"
            aws cloudformation delete-stack --stack-name "$stack_name" --region ${REGION} 2>/dev/null || true
        fi
    done
    log_success "Demo CloudFormation stacks processed"
    
    # 2. CloudWatch log groups (old streams only)
    log_cleanup "Cleaning old CloudWatch log streams..."
    aws logs describe-log-groups --log-group-name-prefix '/aws/lambda/custodian-' --query 'logGroups[].logGroupName' --output text --region ${REGION} | while read -r log_group; do
        if [[ -n "$log_group" ]] && [[ "$log_group" != "None" ]]; then
            # Delete old log streams (older than 24 hours)
            CUTOFF_TIME=$(($(date +%s) - 86400))000
            aws logs describe-log-streams --log-group-name "$log_group" --query "logStreams[?lastEventTime<\`$CUTOFF_TIME\`].logStreamName" --output text --region ${REGION} | while read -r stream; do
                if [[ -n "$stream" ]] && [[ "$stream" != "None" ]]; then
                    echo "  🗑️ Old Log Stream: $stream"
                    aws logs delete-log-stream --log-group-name "$log_group" --log-stream-name "$stream" --region ${REGION} 2>/dev/null || true
                fi
            done
        fi
    done
    log_success "Old CloudWatch log streams processed"
    
    # 3. Temporary files
    log_cleanup "Removing temporary files..."
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
    rm -f /tmp/custodian-*.json
    log_success "Temporary files cleaned"
}

# Wait for resources to fully terminate
wait_for_termination() {
    log_info "Phase 4: Waiting for Resource Termination"
    echo "─────────────────────────────────────────────────"
    
    log_info "Waiting for EC2 instances to terminate (up to 5 minutes)..."
    for i in {1..30}; do
        RUNNING_COUNT=$(aws ec2 describe-instances --filters "Name=tag:TestResource,Values=true" "Name=instance-state-name,Values=running,pending,stopping" --query 'length(Reservations[].Instances[])' --output text --region ${REGION} || echo "0")
        if [[ "$RUNNING_COUNT" -eq 0 ]]; then
            log_success "All demo instances terminated"
            break
        else
            echo "  ⏳ $RUNNING_COUNT instances still terminating... (attempt $i/30)"
            sleep 10
        fi
    done
    
    log_info "Waiting for CloudFormation stacks to delete (up to 3 minutes)..."
    for i in {1..18}; do
        STACK_COUNT=$(aws cloudformation list-stacks --stack-status-filter DELETE_IN_PROGRESS --query 'length(StackSummaries[?contains(StackName, `demo`) || contains(StackName, `test`) || contains(StackName, `custodian`)])' --output text --region ${REGION} || echo "0")
        if [[ "$STACK_COUNT" -eq 0 ]]; then
            log_success "All demo CloudFormation stacks deleted"
            break
        else
            echo "  ⏳ $STACK_COUNT stacks still deleting... (attempt $i/18)"
            sleep 10
        fi
    done
}

# Final verification
verify_cleanup() {
    log_info "Phase 5: Cleanup Verification"
    echo "─────────────────────────────────────────────────"
    
    # Check remaining resources
    REMAINING_INSTANCES=$(aws ec2 describe-instances --filters "Name=tag:TestResource,Values=true" "Name=instance-state-name,Values=running,pending,stopping" --query 'length(Reservations[].Instances[])' --output text --region ${REGION} || echo "0")
    REMAINING_BUCKETS=$(aws s3 ls | grep -E "(custodian-test|custodian-macie|demo|test)" | wc -l || echo "0")
    REMAINING_USERS=$(aws iam list-users --query 'length(Users[?starts_with(UserName, `custodian-test`)])' --output text || echo "0")
    REMAINING_ROLES=$(aws iam list-roles --query 'length(Roles[?starts_with(RoleName, `CustodianTestRole`)])' --output text || echo "0")
    
    echo "📊 Cleanup Verification Results:"
    echo "  🖥️ EC2 Instances: $REMAINING_INSTANCES remaining"
    echo "  📦 S3 Buckets: $REMAINING_BUCKETS remaining"
    echo "  👤 IAM Users: $REMAINING_USERS remaining"
    echo "  🔑 IAM Roles: $REMAINING_ROLES remaining"
    
    if [[ "$REMAINING_INSTANCES" -eq 0 ]] && [[ "$REMAINING_BUCKETS" -eq 0 ]] && [[ "$REMAINING_USERS" -eq 0 ]] && [[ "$REMAINING_ROLES" -eq 0 ]]; then
        log_success "Cleanup completed successfully! No demo resources remain."
    else
        log_warning "Some resources may still be terminating. Check AWS console for final status."
    fi
}

# Main execution
main() {
    echo "╔═════════════════════════════════════════════════════════════╗"
    echo "║       Cloud Custodian Demo Resource Cleanup Tool           ║"
    echo "╚═════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is required but not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Show current AWS context
    echo "AWS Context:"
    echo "  Account: $(aws sts get-caller-identity --query Account --output text)"
    echo "  User/Role: $(aws sts get-caller-identity --query Arn --output text)"
    echo "  Region: $REGION"
    echo ""
    
    # Parse command line arguments
    CLEANUP_TYPE="comprehensive"
    FORCE_YES=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --security-only)
                CLEANUP_TYPE="security"
                shift
                ;;
            --demos-only)
                CLEANUP_TYPE="demos"
                shift
                ;;
            --comprehensive)
                CLEANUP_TYPE="comprehensive"
                shift
                ;;
            --yes|-y)
                FORCE_YES=true
                shift
                ;;
            --region)
                REGION="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --security-only    Clean up security test resources only"
                echo "  --demos-only       Clean up EC2/RDS/EBS demo resources only"
                echo "  --comprehensive    Clean up all demo resources (default)"
                echo "  --yes, -y          Skip confirmation prompt"
                echo "  --region REGION    AWS region (default: us-east-1)"
                echo "  --help, -h         Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0                            # Full interactive cleanup"
                echo "  $0 --security-only            # Security tests only"
                echo "  $0 --comprehensive --yes      # Full cleanup without confirmation"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Confirmation (unless --yes specified)
    if [[ "$FORCE_YES" != true ]]; then
        case $CLEANUP_TYPE in
            security)
                confirm_cleanup "Security Test Resources Only"
                ;;
            demos)
                confirm_cleanup "EC2/RDS/EBS Demo Resources Only"
                ;;
            comprehensive)
                confirm_cleanup "ALL Demo Resources (Comprehensive)"
                ;;
        esac
    fi
    
    # Execute cleanup based on type
    case $CLEANUP_TYPE in
        security)
            cleanup_security_tests
            ;;
        demos)
            cleanup_demo_resources
            ;;
        comprehensive)
            cleanup_security_tests
            echo ""
            cleanup_demo_resources
            echo ""
            cleanup_advanced_resources
            echo ""
            wait_for_termination
            ;;
    esac
    
    echo ""
    verify_cleanup
    
    echo ""
    echo "╔═════════════════════════════════════════════════════════════╗"
    echo "║                    Cleanup Complete!                       ║"
    echo "╚═════════════════════════════════════════════════════════════╝"
    echo ""
    echo "💡 Next Steps:"
    echo "  • Check AWS Console to verify resource deletion"
    echo "  • Review any remaining resources manually"
    echo "  • Run this script again if needed"
    echo ""
    echo "For support: srinivasula.yallala@optum.com"
}

# Run main function
main "$@"