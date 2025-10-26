#!/bin/bash

# ==============================================================================
# Cloud Custodian Step Function Cleanup Script
# ==============================================================================
# This script removes all resources created by the Step Function deployment,
# including Lambda functions, Step Functions, IAM roles, and supporting resources.
#
# Prerequisites:
# - AWS CLI configured with appropriate permissions
# - Resources were created by deploy-stepfunction-demo.sh
#
# Usage: ./cleanup-stepfunction-demo.sh [REGION] [ACCOUNT_ID] [--force]
# ==============================================================================

set -e  # Exit on any error

# Script configuration
SCRIPT_NAME="Cloud Custodian Step Function Cleanup"
SCRIPT_VERSION="1.0.0"
START_TIME=$(date +%s)

# AWS Configuration
AWS_REGION="${1:-us-west-2}"
AWS_ACCOUNT_ID="${2:-$(aws sts get-caller-identity --query Account --output text)}"
FORCE_CLEANUP="${3:-}"

# Resource Names (must match deployment script)
STEP_FUNCTION_NAME="EC2PublicInstanceRemediation"
IAM_ROLE_NAME="cloud-custodian-stepfunction-role"
LAMBDA_ROLE_NAME="cloud-custodian-lambda-role"
SNS_TOPIC_NAME="cloud-custodian-security-alerts"
DYNAMODB_TABLE_NAME="cloud-custodian-review-decisions"
DYNAMODB_APPROVALS_TABLE="cloud-custodian-approvals"

# Lambda Functions to clean up
declare -A LAMBDA_FUNCTIONS=(
    ["EC2-PublicInstance-Notifier"]="notifier.py"
    ["EC2-PublicInstance-Tagger"]="tagger.py"
    ["EC2-PublicInstance-RiskEvaluator"]="risk-evaluator.py"
    ["EC2-PublicInstance-Stopper"]="stopper.py"
    ["EC2-PublicInstance-Monitor"]="monitor.py"
    ["EC2-PublicInstance-Verifier"]="verifier.py"
    ["EC2-PublicInstance-ReviewChecker"]="review-checker.py"
    ["EC2-PublicInstance-Approver"]="approver.py"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Cleanup tracking
RESOURCES_FOUND=0
RESOURCES_DELETED=0
RESOURCES_FAILED=0

# ==============================================================================
# Utility Functions
# ==============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NC}  [$timestamp] $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC}  [$timestamp] $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} [$timestamp] $message" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} [$timestamp] $message" ;;
        "STEP")  echo -e "${CYAN}[STEP]${NC}  [$timestamp] $message" ;;
        *)       echo -e "[$timestamp] $message" ;;
    esac
}

confirm_cleanup() {
    if [[ "$FORCE_CLEANUP" == "--force" ]]; then
        log "WARN" "Force cleanup mode enabled, skipping confirmation"
        return 0
    fi
    
    echo
    echo -e "${RED}⚠️  WARNING: This will permanently delete all Step Function resources!${NC}"
    echo
    echo "The following resources will be deleted:"
    echo "  • Step Function: $STEP_FUNCTION_NAME"
    echo "  • Lambda Functions: ${#LAMBDA_FUNCTIONS[@]} functions"
    echo "  • IAM Roles: $IAM_ROLE_NAME, $LAMBDA_ROLE_NAME"
    echo "  • SNS Topic: $SNS_TOPIC_NAME"
    echo "  • DynamoDB Tables: $DYNAMODB_TABLE_NAME, $DYNAMODB_APPROVALS_TABLE"
    echo "  • CloudWatch Logs groups"
    echo "  • CloudWatch Alarms (if any)"
    echo "  • Cloud Custodian policies and resources"
    echo
    echo -e "${YELLOW}Region: $AWS_REGION${NC}"
    echo -e "${YELLOW}Account: $AWS_ACCOUNT_ID${NC}"
    echo
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "INFO" "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    read -p "Type 'DELETE' to confirm permanent deletion: " -r
    if [[ "$REPLY" != "DELETE" ]]; then
        log "INFO" "Cleanup cancelled - confirmation text didn't match"
        exit 0
    fi
    
    log "INFO" "Cleanup confirmed, proceeding..."
}

check_prerequisites() {
    log "STEP" "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI is not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS credentials not configured"
        exit 1
    fi
    
    log "INFO" "Prerequisites satisfied"
}

# ==============================================================================
# Resource Inventory Functions
# ==============================================================================

inventory_resources() {
    log "STEP" "Taking inventory of resources to cleanup..."
    
    local found=0
    
    # Check Step Function
    if aws stepfunctions describe-state-machine \
        --state-machine-arn "arn:aws:states:$AWS_REGION:$AWS_ACCOUNT_ID:stateMachine:$STEP_FUNCTION_NAME" \
        --region "$AWS_REGION" &> /dev/null; then
        log "INFO" "Found Step Function: $STEP_FUNCTION_NAME"
        ((found++))
    fi
    
    # Check Lambda functions
    for function_name in "${!LAMBDA_FUNCTIONS[@]}"; do
        if aws lambda get-function --function-name "$function_name" --region "$AWS_REGION" &> /dev/null; then
            log "INFO" "Found Lambda function: $function_name"
            ((found++))
        fi
    done
    
    # Check IAM roles
    if aws iam get-role --role-name "$IAM_ROLE_NAME" &> /dev/null; then
        log "INFO" "Found IAM role: $IAM_ROLE_NAME"
        ((found++))
    fi
    
    if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &> /dev/null; then
        log "INFO" "Found IAM role: $LAMBDA_ROLE_NAME"
        ((found++))
    fi
    
    # Check SNS topic
    if aws sns get-topic-attributes \
        --topic-arn "arn:aws:sns:$AWS_REGION:$AWS_ACCOUNT_ID:$SNS_TOPIC_NAME" &> /dev/null; then
        log "INFO" "Found SNS topic: $SNS_TOPIC_NAME"
        ((found++))
    fi
    
    # Check DynamoDB tables
    if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE_NAME" --region "$AWS_REGION" &> /dev/null; then
        log "INFO" "Found DynamoDB table: $DYNAMODB_TABLE_NAME"
        ((found++))
    fi
    
    if aws dynamodb describe-table --table-name "$DYNAMODB_APPROVALS_TABLE" --region "$AWS_REGION" &> /dev/null; then
        log "INFO" "Found DynamoDB table: $DYNAMODB_APPROVALS_TABLE"
        ((found++))
    fi
    
    RESOURCES_FOUND=$found
    log "INFO" "Found $RESOURCES_FOUND resources to cleanup"
    
    if [[ $RESOURCES_FOUND -eq 0 ]]; then
        log "INFO" "No resources found to cleanup"
        exit 0
    fi
}

# ==============================================================================
# Cleanup Functions
# ==============================================================================

cleanup_step_function() {
    log "STEP" "Cleaning up Step Function..."
    
    local state_machine_arn="arn:aws:states:$AWS_REGION:$AWS_ACCOUNT_ID:stateMachine:$STEP_FUNCTION_NAME"
    
    if aws stepfunctions describe-state-machine \
        --state-machine-arn "$state_machine_arn" \
        --region "$AWS_REGION" &> /dev/null; then
        
        log "INFO" "Deleting Step Function: $STEP_FUNCTION_NAME"
        
        # Stop any running executions first
        local executions=$(aws stepfunctions list-executions \
            --state-machine-arn "$state_machine_arn" \
            --status-filter RUNNING \
            --region "$AWS_REGION" \
            --query 'executions[].executionArn' \
            --output text)
        
        if [[ -n "$executions" ]]; then
            log "WARN" "Stopping running executions..."
            for execution_arn in $executions; do
                aws stepfunctions stop-execution \
                    --execution-arn "$execution_arn" \
                    --region "$AWS_REGION" || true
            done
            
            # Wait a moment for executions to stop
            sleep 10
        fi
        
        # Delete the state machine
        if aws stepfunctions delete-state-machine \
            --state-machine-arn "$state_machine_arn" \
            --region "$AWS_REGION"; then
            log "INFO" "✓ Deleted Step Function: $STEP_FUNCTION_NAME"
            ((RESOURCES_DELETED++))
        else
            log "ERROR" "✗ Failed to delete Step Function: $STEP_FUNCTION_NAME"
            ((RESOURCES_FAILED++))
        fi
    else
        log "INFO" "Step Function not found: $STEP_FUNCTION_NAME"
    fi
}

cleanup_lambda_functions() {
    log "STEP" "Cleaning up Lambda functions..."
    
    for function_name in "${!LAMBDA_FUNCTIONS[@]}"; do
        if aws lambda get-function --function-name "$function_name" --region "$AWS_REGION" &> /dev/null; then
            log "INFO" "Deleting Lambda function: $function_name"
            
            if aws lambda delete-function \
                --function-name "$function_name" \
                --region "$AWS_REGION"; then
                log "INFO" "✓ Deleted Lambda function: $function_name"
                ((RESOURCES_DELETED++))
            else
                log "ERROR" "✗ Failed to delete Lambda function: $function_name"
                ((RESOURCES_FAILED++))
            fi
        else
            log "INFO" "Lambda function not found: $function_name"
        fi
    done
}

cleanup_cloudwatch_resources() {
    log "STEP" "Cleaning up CloudWatch resources..."
    
    # Delete log groups for Lambda functions
    for function_name in "${!LAMBDA_FUNCTIONS[@]}"; do
        local log_group="/aws/lambda/$function_name"
        
        if aws logs describe-log-groups \
            --log-group-name-prefix "$log_group" \
            --region "$AWS_REGION" \
            --query 'logGroups[0].logGroupName' \
            --output text 2>/dev/null | grep -q "$log_group"; then
            
            log "INFO" "Deleting log group: $log_group"
            
            if aws logs delete-log-group \
                --log-group-name "$log_group" \
                --region "$AWS_REGION"; then
                log "INFO" "✓ Deleted log group: $log_group"
                ((RESOURCES_DELETED++))
            else
                log "ERROR" "✗ Failed to delete log group: $log_group"
                ((RESOURCES_FAILED++))
            fi
        fi
    done
    
    # Delete Step Function log group
    local sf_log_group="/aws/stepfunctions/$STEP_FUNCTION_NAME"
    if aws logs describe-log-groups \
        --log-group-name-prefix "$sf_log_group" \
        --region "$AWS_REGION" \
        --query 'logGroups[0].logGroupName' \
        --output text 2>/dev/null | grep -q "$sf_log_group"; then
        
        log "INFO" "Deleting Step Function log group: $sf_log_group"
        aws logs delete-log-group \
            --log-group-name "$sf_log_group" \
            --region "$AWS_REGION" || true
    fi
    
    # Delete monitoring-related log groups
    local monitoring_log_group="/aws/ec2/public-instance-monitoring"
    if aws logs describe-log-groups \
        --log-group-name-prefix "$monitoring_log_group" \
        --region "$AWS_REGION" \
        --query 'logGroups[].logGroupName' \
        --output text 2>/dev/null; then
        
        log "INFO" "Deleting monitoring log groups..."
        aws logs describe-log-groups \
            --log-group-name-prefix "$monitoring_log_group" \
            --region "$AWS_REGION" \
            --query 'logGroups[].logGroupName' \
            --output text | xargs -r -n1 aws logs delete-log-group \
            --region "$AWS_REGION" \
            --log-group-name || true
    fi
    
    # Delete CloudWatch alarms created by monitoring function
    log "INFO" "Deleting CloudWatch alarms..."
    local alarm_prefix="PublicEC2-"
    
    aws cloudwatch describe-alarms \
        --alarm-name-prefix "$alarm_prefix" \
        --region "$AWS_REGION" \
        --query 'MetricAlarms[].AlarmName' \
        --output text | xargs -r -n1 aws cloudwatch delete-alarms \
        --region "$AWS_REGION" \
        --alarm-names || true
    
    # Delete CloudWatch dashboard
    local dashboard_name="PublicEC2InstanceMonitoring"
    if aws cloudwatch get-dashboard \
        --dashboard-name "$dashboard_name" \
        --region "$AWS_REGION" &> /dev/null; then
        
        log "INFO" "Deleting CloudWatch dashboard: $dashboard_name"
        aws cloudwatch delete-dashboards \
            --dashboard-names "$dashboard_name" \
            --region "$AWS_REGION" || true
    fi
}

cleanup_iam_roles() {
    log "STEP" "Cleaning up IAM roles..."
    
    # Cleanup Step Function role
    cleanup_single_iam_role "$IAM_ROLE_NAME"
    
    # Cleanup Lambda role
    cleanup_single_iam_role "$LAMBDA_ROLE_NAME"
}

cleanup_single_iam_role() {
    local role_name="$1"
    
    if aws iam get-role --role-name "$role_name" &> /dev/null; then
        log "INFO" "Cleaning up IAM role: $role_name"
        
        # Detach managed policies
        local attached_policies=$(aws iam list-attached-role-policies \
            --role-name "$role_name" \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text)
        
        for policy_arn in $attached_policies; do
            log "INFO" "Detaching policy: $policy_arn"
            aws iam detach-role-policy \
                --role-name "$role_name" \
                --policy-arn "$policy_arn" || true
        done
        
        # Delete inline policies
        local inline_policies=$(aws iam list-role-policies \
            --role-name "$role_name" \
            --query 'PolicyNames' \
            --output text)
        
        for policy_name in $inline_policies; do
            log "INFO" "Deleting inline policy: $policy_name"
            aws iam delete-role-policy \
                --role-name "$role_name" \
                --policy-name "$policy_name" || true
        done
        
        # Delete the role
        if aws iam delete-role --role-name "$role_name"; then
            log "INFO" "✓ Deleted IAM role: $role_name"
            ((RESOURCES_DELETED++))
        else
            log "ERROR" "✗ Failed to delete IAM role: $role_name"
            ((RESOURCES_FAILED++))
        fi
    else
        log "INFO" "IAM role not found: $role_name"
    fi
}

cleanup_supporting_resources() {
    log "STEP" "Cleaning up supporting resources..."
    
    # Cleanup SNS topic
    local topic_arn="arn:aws:sns:$AWS_REGION:$AWS_ACCOUNT_ID:$SNS_TOPIC_NAME"
    
    if aws sns get-topic-attributes --topic-arn "$topic_arn" &> /dev/null; then
        log "INFO" "Deleting SNS topic: $SNS_TOPIC_NAME"
        
        if aws sns delete-topic --topic-arn "$topic_arn"; then
            log "INFO" "✓ Deleted SNS topic: $SNS_TOPIC_NAME"
            ((RESOURCES_DELETED++))
        else
            log "ERROR" "✗ Failed to delete SNS topic: $SNS_TOPIC_NAME"
            ((RESOURCES_FAILED++))
        fi
    else
        log "INFO" "SNS topic not found: $SNS_TOPIC_NAME"
    fi
    
    # Cleanup DynamoDB tables
    cleanup_dynamodb_table "$DYNAMODB_TABLE_NAME"
    cleanup_dynamodb_table "$DYNAMODB_APPROVALS_TABLE"
}

cleanup_dynamodb_table() {
    local table_name="$1"
    
    if aws dynamodb describe-table --table-name "$table_name" --region "$AWS_REGION" &> /dev/null; then
        log "INFO" "Deleting DynamoDB table: $table_name"
        
        if aws dynamodb delete-table --table-name "$table_name" --region "$AWS_REGION"; then
            log "INFO" "✓ Deleted DynamoDB table: $table_name"
            ((RESOURCES_DELETED++))
            
            # Wait for table deletion
            log "INFO" "Waiting for table deletion to complete..."
            aws dynamodb wait table-not-exists --table-name "$table_name" --region "$AWS_REGION" || true
        else
            log "ERROR" "✗ Failed to delete DynamoDB table: $table_name"
            ((RESOURCES_FAILED++))
        fi
    else
        log "INFO" "DynamoDB table not found: $table_name"
    fi
}

cleanup_custodian_resources() {
    log "STEP" "Cleaning up Cloud Custodian resources..."
    
    # Delete CloudWatch Events rules created by Cloud Custodian
    log "INFO" "Deleting CloudWatch Events rules..."
    
    local custodian_rules=$(aws events list-rules \
        --name-prefix "custodian-" \
        --region "$AWS_REGION" \
        --query 'Rules[].Name' \
        --output text)
    
    for rule_name in $custodian_rules; do
        if [[ "$rule_name" == *"ec2-public"* ]]; then
            log "INFO" "Removing targets from rule: $rule_name"
            
            # Get rule targets
            local targets=$(aws events list-targets-by-rule \
                --rule "$rule_name" \
                --region "$AWS_REGION" \
                --query 'Targets[].Id' \
                --output text)
            
            if [[ -n "$targets" ]]; then
                # Remove targets
                local target_ids=""
                for target_id in $targets; do
                    target_ids="$target_ids Id=$target_id"
                done
                
                aws events remove-targets \
                    --rule "$rule_name" \
                    --ids $targets \
                    --region "$AWS_REGION" || true
            fi
            
            # Delete the rule
            log "INFO" "Deleting rule: $rule_name"
            aws events delete-rule \
                --name "$rule_name" \
                --region "$AWS_REGION" || true
        fi
    done
    
    # Delete any Lambda functions created by Cloud Custodian for these policies
    log "INFO" "Checking for additional Cloud Custodian Lambda functions..."
    
    local custodian_functions=$(aws lambda list-functions \
        --region "$AWS_REGION" \
        --query 'Functions[?contains(FunctionName, `custodian-ec2-public`)].FunctionName' \
        --output text)
    
    for function_name in $custodian_functions; do
        log "INFO" "Deleting Cloud Custodian function: $function_name"
        aws lambda delete-function \
            --function-name "$function_name" \
            --region "$AWS_REGION" || true
    done
}

# ==============================================================================
# Main Cleanup Function
# ==============================================================================

main() {
    log "INFO" "Starting $SCRIPT_NAME v$SCRIPT_VERSION"
    log "INFO" "AWS Region: $AWS_REGION"
    log "INFO" "AWS Account: $AWS_ACCOUNT_ID"
    
    # Pre-cleanup checks
    check_prerequisites
    inventory_resources
    
    # Confirm cleanup
    confirm_cleanup
    
    # Execute cleanup in reverse order of creation
    cleanup_custodian_resources
    cleanup_step_function
    cleanup_lambda_functions
    cleanup_cloudwatch_resources
    cleanup_iam_roles
    cleanup_supporting_resources
    
    # Final summary
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    
    log "INFO" "Cleanup completed in ${duration} seconds"
    
    # Display cleanup summary
    cat << EOF

📊 CLEANUP SUMMARY
═══════════════════════════════════════════════════════════════
Region: $AWS_REGION
Account: $AWS_ACCOUNT_ID

📈 Results:
─────────────────────────────────────────────────────────────
• Resources Found: $RESOURCES_FOUND
• Resources Deleted: $RESOURCES_DELETED
• Resources Failed: $RESOURCES_FAILED

EOF

    if [[ $RESOURCES_FAILED -eq 0 ]]; then
        log "INFO" "🎉 Cleanup completed successfully!"
        cat << EOF
✅ All Step Function resources have been removed
✅ No AWS charges should continue for these resources
✅ IAM roles and policies have been cleaned up
✅ CloudWatch logs and alarms have been removed

EOF
    else
        log "WARN" "⚠️ Cleanup completed with some failures"
        cat << EOF
⚠️  Some resources could not be deleted automatically
⚠️  Please check the AWS Console for any remaining resources
⚠️  You may need to manually delete some resources

Common reasons for deletion failures:
• IAM eventual consistency delays
• Resources in use by other services
• Insufficient permissions
• Dependencies not cleaned up

EOF
    fi
    
    log "INFO" "Cleanup process finished"
}

# Run main function
main "$@"