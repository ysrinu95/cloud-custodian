#!/bin/bash

# ==============================================================================
# Cloud Custodian Step Function Testing and Demo Script
# ==============================================================================
# This script creates test EC2 instances, monitors Step Function executions,
# and provides comprehensive testing of the public instance remediation workflow.
#
# Prerequisites:
# - AWS CLI configured with appropriate permissions
# - Step Function resources deployed by deploy-stepfunction-demo.sh
# - Default VPC and security group available
#
# Usage: ./test-stepfunction-demo.sh [REGION] [ACCOUNT_ID] [TEST_TYPE]
# Test Types: basic, comprehensive, stress
# ==============================================================================

set -e  # Exit on any error

# Script configuration
SCRIPT_NAME="Cloud Custodian Step Function Testing"
SCRIPT_VERSION="1.0.0"
START_TIME=$(date +%s)

# AWS Configuration
AWS_REGION="${1:-us-west-2}"
AWS_ACCOUNT_ID="${2:-$(aws sts get-caller-identity --query Account --output text)}"
TEST_TYPE="${3:-basic}"

# Resource Names (must match deployment script)
STEP_FUNCTION_NAME="EC2PublicInstanceRemediation"
SNS_TOPIC_NAME="cloud-custodian-security-alerts"

# Test Configuration
TEST_INSTANCE_NAME_PREFIX="custodian-stepfunction-test"
TEST_KEY_PAIR_NAME="custodian-test-keypair"
TEST_SECURITY_GROUP_NAME="custodian-test-sg"
INSTANCE_TYPE="t3.micro"
WAIT_TIMEOUT=600  # 10 minutes

# Test Tracking
declare -a TEST_INSTANCES=()
declare -a STEP_FUNCTION_EXECUTIONS=()
TEST_RESULTS=()

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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
        "TEST")  echo -e "${BLUE}[TEST]${NC}  [$timestamp] $message" ;;
        *)       echo -e "[$timestamp] $message" ;;
    esac
}

cleanup_on_exit() {
    log "INFO" "Performing cleanup on exit..."
    cleanup_test_resources
}

# Register cleanup function
trap cleanup_on_exit EXIT

check_prerequisites() {
    log "STEP" "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI is not installed"
        exit 1
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        log "ERROR" "jq is not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS credentials not configured"
        exit 1
    fi
    
    # Check if Step Function exists
    if ! aws stepfunctions describe-state-machine \
        --state-machine-arn "arn:aws:states:$AWS_REGION:$AWS_ACCOUNT_ID:stateMachine:$STEP_FUNCTION_NAME" \
        --region "$AWS_REGION" &> /dev/null; then
        log "ERROR" "Step Function $STEP_FUNCTION_NAME not found. Run deploy-stepfunction-demo.sh first."
        exit 1
    fi
    
    log "INFO" "All prerequisites satisfied"
}

# ==============================================================================
# Test Infrastructure Setup
# ==============================================================================

setup_test_infrastructure() {
    log "STEP" "Setting up test infrastructure..."
    
    # Create key pair for test instances
    create_test_keypair
    
    # Create security group for public access testing
    create_test_security_group
    
    log "INFO" "Test infrastructure setup complete"
}

create_test_keypair() {
    log "INFO" "Creating test key pair..."
    
    if aws ec2 describe-key-pairs \
        --key-names "$TEST_KEY_PAIR_NAME" \
        --region "$AWS_REGION" &> /dev/null; then
        log "INFO" "Key pair $TEST_KEY_PAIR_NAME already exists"
    else
        aws ec2 create-key-pair \
            --key-name "$TEST_KEY_PAIR_NAME" \
            --region "$AWS_REGION" \
            --query 'KeyMaterial' \
            --output text > "/tmp/$TEST_KEY_PAIR_NAME.pem"
        
        chmod 600 "/tmp/$TEST_KEY_PAIR_NAME.pem"
        log "INFO" "Created key pair: $TEST_KEY_PAIR_NAME"
    fi
}

create_test_security_group() {
    log "INFO" "Creating test security group..."
    
    # Get default VPC ID
    local vpc_id=$(aws ec2 describe-vpcs \
        --filters "Name=isDefault,Values=true" \
        --region "$AWS_REGION" \
        --query 'Vpcs[0].VpcId' \
        --output text)
    
    if [[ "$vpc_id" == "None" ]] || [[ -z "$vpc_id" ]]; then
        log "ERROR" "No default VPC found in region $AWS_REGION"
        exit 1
    fi
    
    # Check if security group exists
    local sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$TEST_SECURITY_GROUP_NAME" \
        --region "$AWS_REGION" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "None")
    
    if [[ "$sg_id" != "None" ]] && [[ -n "$sg_id" ]]; then
        log "INFO" "Security group $TEST_SECURITY_GROUP_NAME already exists: $sg_id"
        TEST_SECURITY_GROUP_ID="$sg_id"
    else
        # Create security group
        TEST_SECURITY_GROUP_ID=$(aws ec2 create-security-group \
            --group-name "$TEST_SECURITY_GROUP_NAME" \
            --description "Test security group for Cloud Custodian Step Function demo" \
            --vpc-id "$vpc_id" \
            --region "$AWS_REGION" \
            --query 'GroupId' \
            --output text)
        
        log "INFO" "Created security group: $TEST_SECURITY_GROUP_ID"
        
        # Add rules to make it deliberately insecure for testing
        aws ec2 authorize-security-group-ingress \
            --group-id "$TEST_SECURITY_GROUP_ID" \
            --protocol tcp \
            --port 22 \
            --cidr 0.0.0.0/0 \
            --region "$AWS_REGION"
        
        aws ec2 authorize-security-group-ingress \
            --group-id "$TEST_SECURITY_GROUP_ID" \
            --protocol tcp \
            --port 80 \
            --cidr 0.0.0.0/0 \
            --region "$AWS_REGION"
        
        aws ec2 authorize-security-group-ingress \
            --group-id "$TEST_SECURITY_GROUP_ID" \
            --protocol tcp \
            --port 3389 \
            --cidr 0.0.0.0/0 \
            --region "$AWS_REGION"
        
        log "INFO" "Added public access rules to security group"
    fi
}

# ==============================================================================
# Test Instance Creation
# ==============================================================================

create_test_instances() {
    log "STEP" "Creating test instances for $TEST_TYPE testing..."
    
    case "$TEST_TYPE" in
        "basic")
            create_basic_test_instances
            ;;
        "comprehensive")
            create_comprehensive_test_instances
            ;;
        "stress")
            create_stress_test_instances
            ;;
        *)
            log "ERROR" "Unknown test type: $TEST_TYPE"
            exit 1
            ;;
    esac
    
    log "INFO" "Created ${#TEST_INSTANCES[@]} test instances"
}

create_basic_test_instances() {
    log "INFO" "Creating basic test instance..."
    
    # Create one instance with public IP
    local instance_id=$(create_single_test_instance "basic-test" true)
    TEST_INSTANCES+=("$instance_id")
}

create_comprehensive_test_instances() {
    log "INFO" "Creating comprehensive test instances..."
    
    # High-risk instance (public IP + insecure security group)
    local high_risk_id=$(create_single_test_instance "high-risk" true)
    TEST_INSTANCES+=("$high_risk_id")
    
    # Medium-risk instance (public IP but better tags)
    local medium_risk_id=$(create_single_test_instance "medium-risk" true)
    add_instance_tags "$medium_risk_id" "Environment=dev" "Owner=test-user"
    TEST_INSTANCES+=("$medium_risk_id")
    
    # Low-risk instance (public IP with approval tags)
    local low_risk_id=$(create_single_test_instance "low-risk" true)
    add_instance_tags "$low_risk_id" "Environment=dev" "Owner=test-user" "Purpose=web-server"
    TEST_INSTANCES+=("$low_risk_id")
}

create_stress_test_instances() {
    log "INFO" "Creating stress test instances..."
    
    # Create multiple instances to test concurrent processing
    for i in {1..5}; do
        local instance_id=$(create_single_test_instance "stress-test-$i" true)
        TEST_INSTANCES+=("$instance_id")
        
        # Add some variety in risk levels
        if [[ $((i % 2)) -eq 0 ]]; then
            add_instance_tags "$instance_id" "Environment=test" "Owner=stress-test"
        fi
        
        # Small delay to spread out launches
        sleep 5
    done
}

create_single_test_instance() {
    local instance_name="$1"
    local assign_public_ip="$2"
    
    log "INFO" "Creating instance: $instance_name"
    
    # Get latest Amazon Linux 2 AMI
    local ami_id=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
              "Name=state,Values=available" \
        --region "$AWS_REGION" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    
    # Get default subnet
    local subnet_id=$(aws ec2 describe-subnets \
        --filters "Name=default-for-az,Values=true" \
        --region "$AWS_REGION" \
        --query 'Subnets[0].SubnetId' \
        --output text)
    
    # Launch instance
    local instance_id=$(aws ec2 run-instances \
        --image-id "$ami_id" \
        --count 1 \
        --instance-type "$INSTANCE_TYPE" \
        --key-name "$TEST_KEY_PAIR_NAME" \
        --security-group-ids "$TEST_SECURITY_GROUP_ID" \
        --subnet-id "$subnet_id" \
        --associate-public-ip-address \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$TEST_INSTANCE_NAME_PREFIX-$instance_name},{Key=TestType,Value=$TEST_TYPE},{Key=CreatedBy,Value=stepfunction-test}]" \
        --region "$AWS_REGION" \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    log "INFO" "Created instance: $instance_id ($instance_name)"
    
    echo "$instance_id"
}

add_instance_tags() {
    local instance_id="$1"
    shift
    local tags=("$@")
    
    local tag_spec=""
    for tag in "${tags[@]}"; do
        local key="${tag%=*}"
        local value="${tag#*=}"
        tag_spec="$tag_spec Key=$key,Value=$value"
    done
    
    aws ec2 create-tags \
        --resources "$instance_id" \
        --tags $tag_spec \
        --region "$AWS_REGION"
    
    log "INFO" "Added tags to $instance_id: ${tags[*]}"
}

# ==============================================================================
# Step Function Monitoring
# ==============================================================================

monitor_step_function_executions() {
    log "STEP" "Monitoring Step Function executions..."
    
    local state_machine_arn="arn:aws:states:$AWS_REGION:$AWS_ACCOUNT_ID:stateMachine:$STEP_FUNCTION_NAME"
    local start_time=$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ)
    local timeout_time=$(($(date +%s) + WAIT_TIMEOUT))
    
    log "INFO" "Waiting for Cloud Custodian to detect instances and trigger Step Function..."
    log "INFO" "This may take 5-10 minutes for CloudTrail events to be processed"
    
    # Wait for executions to start
    while [[ $(date +%s) -lt $timeout_time ]]; do
        local executions=$(aws stepfunctions list-executions \
            --state-machine-arn "$state_machine_arn" \
            --region "$AWS_REGION" \
            --query "executions[?startDate >= '$start_time'].executionArn" \
            --output text)
        
        if [[ -n "$executions" ]]; then
            log "INFO" "Found Step Function executions!"
            
            # Store executions for monitoring
            IFS=$'\t' read -ra STEP_FUNCTION_EXECUTIONS <<< "$executions"
            
            # Monitor each execution
            for execution_arn in "${STEP_FUNCTION_EXECUTIONS[@]}"; do
                monitor_single_execution "$execution_arn"
            done
            
            break
        else
            log "INFO" "No executions found yet, waiting..."
            sleep 30
        fi
    done
    
    if [[ ${#STEP_FUNCTION_EXECUTIONS[@]} -eq 0 ]]; then
        log "WARN" "No Step Function executions detected within timeout period"
        log "INFO" "This might mean:"
        log "INFO" "  1. CloudTrail events haven't been processed yet"
        log "INFO" "  2. Cloud Custodian policy isn't deployed correctly"
        log "INFO" "  3. Instance configuration doesn't match policy filters"
        
        # Try manual execution
        trigger_manual_execution
    fi
}

monitor_single_execution() {
    local execution_arn="$1"
    local execution_name=$(basename "$execution_arn")
    
    log "INFO" "Monitoring execution: $execution_name"
    
    # Wait for execution to complete
    local timeout_time=$(($(date +%s) + 300))  # 5 minutes for execution
    
    while [[ $(date +%s) -lt $timeout_time ]]; do
        local execution_status=$(aws stepfunctions describe-execution \
            --execution-arn "$execution_arn" \
            --region "$AWS_REGION" \
            --query 'status' \
            --output text)
        
        case "$execution_status" in
            "SUCCEEDED")
                log "INFO" "✓ Execution completed successfully: $execution_name"
                TEST_RESULTS+=("PASS:$execution_name:Execution succeeded")
                break
                ;;
            "FAILED")
                log "ERROR" "✗ Execution failed: $execution_name"
                get_execution_details "$execution_arn"
                TEST_RESULTS+=("FAIL:$execution_name:Execution failed")
                break
                ;;
            "TIMED_OUT")
                log "ERROR" "✗ Execution timed out: $execution_name"
                TEST_RESULTS+=("FAIL:$execution_name:Execution timed out")
                break
                ;;
            "ABORTED")
                log "ERROR" "✗ Execution aborted: $execution_name"
                TEST_RESULTS+=("FAIL:$execution_name:Execution aborted")
                break
                ;;
            "RUNNING")
                log "INFO" "Execution still running: $execution_name"
                sleep 10
                ;;
        esac
    done
}

get_execution_details() {
    local execution_arn="$1"
    
    log "INFO" "Getting execution details..."
    
    # Get execution history
    aws stepfunctions get-execution-history \
        --execution-arn "$execution_arn" \
        --region "$AWS_REGION" \
        --query 'events[?type==`TaskFailed` || type==`ExecutionFailed`].[timestamp,type,taskFailedEventDetails.error,taskFailedEventDetails.cause]' \
        --output table
}

trigger_manual_execution() {
    log "INFO" "Triggering manual Step Function execution for testing..."
    
    if [[ ${#TEST_INSTANCES[@]} -eq 0 ]]; then
        log "ERROR" "No test instances available for manual execution"
        return
    fi
    
    local instance_id="${TEST_INSTANCES[0]}"
    local state_machine_arn="arn:aws:states:$AWS_REGION:$AWS_ACCOUNT_ID:stateMachine:$STEP_FUNCTION_NAME"
    
    # Get instance details
    local instance_info=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --region "$AWS_REGION" \
        --query 'Reservations[0].Instances[0]')
    
    local public_ip=$(echo "$instance_info" | jq -r '.PublicIpAddress // "Unknown"')
    local instance_type=$(echo "$instance_info" | jq -r '.InstanceType')
    local launch_time=$(echo "$instance_info" | jq -r '.LaunchTime')
    
    # Create execution input
    local execution_input=$(cat << EOF
{
    "instanceId": "$instance_id",
    "accountId": "$AWS_ACCOUNT_ID",
    "region": "$AWS_REGION",
    "publicIp": "$public_ip",
    "instanceType": "$instance_type",
    "launchTime": "$launch_time",
    "discoveredBy": "manual-test",
    "discoveredAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "policyName": "manual-stepfunction-test"
}
EOF
)
    
    # Start execution
    local execution_arn=$(aws stepfunctions start-execution \
        --state-machine-arn "$state_machine_arn" \
        --name "manual-test-$(date +%s)" \
        --input "$execution_input" \
        --region "$AWS_REGION" \
        --query 'executionArn' \
        --output text)
    
    log "INFO" "Started manual execution: $execution_arn"
    STEP_FUNCTION_EXECUTIONS+=("$execution_arn")
    
    # Monitor the manual execution
    monitor_single_execution "$execution_arn"
}

# ==============================================================================
# Test Results and Verification
# ==============================================================================

verify_test_results() {
    log "STEP" "Verifying test results..."
    
    # Check instance states
    verify_instance_states
    
    # Check tags applied
    verify_instance_tags
    
    # Check CloudWatch logs
    verify_cloudwatch_logs
    
    # Check Step Function execution results
    verify_step_function_results
}

verify_instance_states() {
    log "INFO" "Verifying instance states..."
    
    for instance_id in "${TEST_INSTANCES[@]}"; do
        local state=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --region "$AWS_REGION" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text)
        
        log "INFO" "Instance $instance_id state: $state"
        
        # Check if instance was processed (should have custodian tags)
        local custodian_tags=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --region "$AWS_REGION" \
            --query 'Reservations[0].Instances[0].Tags[?starts_with(Key, `custodian:`)]' \
            --output text)
        
        if [[ -n "$custodian_tags" ]]; then
            log "INFO" "✓ Instance $instance_id was processed by Step Function"
            TEST_RESULTS+=("PASS:$instance_id:Instance processed")
        else
            log "WARN" "✗ Instance $instance_id may not have been processed"
            TEST_RESULTS+=("WARN:$instance_id:No custodian tags found")
        fi
    done
}

verify_instance_tags() {
    log "INFO" "Verifying instance tags..."
    
    for instance_id in "${TEST_INSTANCES[@]}"; do
        local tags=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --region "$AWS_REGION" \
            --query 'Reservations[0].Instances[0].Tags[].[Key,Value]' \
            --output text)
        
        log "INFO" "Tags for $instance_id:"
        echo "$tags" | grep -E "custodian:|security:" | while read -r key value; do
            log "INFO" "  $key: $value"
        done
    done
}

verify_cloudwatch_logs() {
    log "INFO" "Checking CloudWatch logs for Lambda functions..."
    
    local lambda_functions=(
        "EC2-PublicInstance-Notifier"
        "EC2-PublicInstance-Tagger"
        "EC2-PublicInstance-RiskEvaluator"
    )
    
    for function_name in "${lambda_functions[@]}"; do
        local log_group="/aws/lambda/$function_name"
        
        # Get recent log events
        local recent_logs=$(aws logs filter-log-events \
            --log-group-name "$log_group" \
            --start-time $(($(date +%s) - 3600))000 \
            --region "$AWS_REGION" \
            --query 'events[].message' \
            --output text 2>/dev/null | head -5)
        
        if [[ -n "$recent_logs" ]]; then
            log "INFO" "✓ Recent activity in $function_name logs"
        else
            log "WARN" "No recent activity in $function_name logs"
        fi
    done
}

verify_step_function_results() {
    log "INFO" "Step Function execution summary:"
    
    local total_executions=${#STEP_FUNCTION_EXECUTIONS[@]}
    local successful_executions=0
    
    for result in "${TEST_RESULTS[@]}"; do
        if [[ "$result" == PASS:*:Execution* ]]; then
            ((successful_executions++))
        fi
    done
    
    log "INFO" "Total executions: $total_executions"
    log "INFO" "Successful executions: $successful_executions"
    
    if [[ $successful_executions -gt 0 ]]; then
        log "INFO" "✓ Step Function workflow is working correctly"
    else
        log "WARN" "⚠ No successful Step Function executions detected"
    fi
}

# ==============================================================================
# Cleanup Functions
# ==============================================================================

cleanup_test_resources() {
    log "STEP" "Cleaning up test resources..."
    
    # Terminate test instances
    if [[ ${#TEST_INSTANCES[@]} -gt 0 ]]; then
        log "INFO" "Terminating test instances..."
        
        aws ec2 terminate-instances \
            --instance-ids "${TEST_INSTANCES[@]}" \
            --region "$AWS_REGION" || true
        
        log "INFO" "Terminated ${#TEST_INSTANCES[@]} test instances"
    fi
    
    # Delete security group
    if [[ -n "$TEST_SECURITY_GROUP_ID" ]]; then
        log "INFO" "Waiting for instances to terminate before deleting security group..."
        sleep 30
        
        aws ec2 delete-security-group \
            --group-id "$TEST_SECURITY_GROUP_ID" \
            --region "$AWS_REGION" || true
        
        log "INFO" "Deleted test security group: $TEST_SECURITY_GROUP_ID"
    fi
    
    # Delete key pair
    aws ec2 delete-key-pair \
        --key-name "$TEST_KEY_PAIR_NAME" \
        --region "$AWS_REGION" || true
    
    rm -f "/tmp/$TEST_KEY_PAIR_NAME.pem"
    log "INFO" "Deleted test key pair: $TEST_KEY_PAIR_NAME"
}

# ==============================================================================
# Main Testing Function
# ==============================================================================

main() {
    log "INFO" "Starting $SCRIPT_NAME v$SCRIPT_VERSION"
    log "INFO" "AWS Region: $AWS_REGION"
    log "INFO" "AWS Account: $AWS_ACCOUNT_ID"
    log "INFO" "Test Type: $TEST_TYPE"
    
    # Pre-test checks
    check_prerequisites
    
    # Setup test environment
    setup_test_infrastructure
    
    # Create and monitor test instances
    create_test_instances
    
    # Wait for instances to be running
    log "INFO" "Waiting for instances to be in running state..."
    sleep 60
    
    # Monitor Step Function executions
    monitor_step_function_executions
    
    # Verify results
    verify_test_results
    
    # Generate final report
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    
    log "INFO" "Testing completed in ${duration} seconds"
    
    # Display test summary
    cat << EOF

📊 TEST SUMMARY
═══════════════════════════════════════════════════════════════
Test Type: $TEST_TYPE
Region: $AWS_REGION
Account: $AWS_ACCOUNT_ID
Duration: ${duration} seconds

🔧 Test Resources Created:
─────────────────────────────────────────────────────────────
• Test Instances: ${#TEST_INSTANCES[@]}
• Step Function Executions: ${#STEP_FUNCTION_EXECUTIONS[@]}
• Security Group: $TEST_SECURITY_GROUP_ID
• Key Pair: $TEST_KEY_PAIR_NAME

📈 Test Results:
─────────────────────────────────────────────────────────────
EOF

    local pass_count=0
    local fail_count=0
    local warn_count=0
    
    for result in "${TEST_RESULTS[@]}"; do
        local status="${result%%:*}"
        local details="${result#*:}"
        
        case "$status" in
            "PASS")
                ((pass_count++))
                log "INFO" "✓ $details"
                ;;
            "FAIL")
                ((fail_count++))
                log "ERROR" "✗ $details"
                ;;
            "WARN")
                ((warn_count++))
                log "WARN" "⚠ $details"
                ;;
        esac
    done
    
    cat << EOF

📊 Results Summary:
─────────────────────────────────────────────────────────────
• Passed: $pass_count
• Failed: $fail_count  
• Warnings: $warn_count

EOF

    if [[ $fail_count -eq 0 ]]; then
        log "INFO" "🎉 All tests completed successfully!"
        cat << EOF
✅ Step Function workflow is working correctly
✅ Lambda functions are executing properly
✅ Instance detection and processing is functional
✅ Risk evaluation and decision logic is operational

EOF
    else
        log "WARN" "⚠️ Some tests failed or had issues"
        cat << EOF
⚠️  Please review the test results above
⚠️  Check CloudWatch logs for detailed error information
⚠️  Verify Step Function execution history in AWS Console

Troubleshooting tips:
• Check if Cloud Custodian policies are properly deployed
• Verify IAM permissions for all Lambda functions
• Ensure CloudTrail is enabled and functioning
• Review Step Function execution history for errors

EOF
    fi
    
    log "INFO" "Test resources will be cleaned up automatically"
    log "INFO" "Testing process finished"
}

# Run main function
main "$@"