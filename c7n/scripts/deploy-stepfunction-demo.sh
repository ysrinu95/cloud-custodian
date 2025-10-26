#!/bin/bash

# ==============================================================================
# Cloud Custodian Step Function Deployment Script
# ==============================================================================
# This script creates all necessary resources for EC2 public instance detection
# and automated remediation using AWS Step Functions and Lambda functions.
#
# Prerequisites:
# - AWS CLI configured with appropriate permissions
# - Python 3.8+ installed
# - Cloud Custodian installed (pip install c7n)
# - jq installed for JSON processing
# - zip utility installed
#
# Usage: ./deploy-stepfunction-demo.sh [REGION] [ACCOUNT_ID]
# ==============================================================================

set -e  # Exit on any error

# Script configuration
SCRIPT_NAME="Cloud Custodian Step Function Deployment"
SCRIPT_VERSION="1.0.0"
START_TIME=$(date +%s)

# AWS Configuration
AWS_REGION="${1:-us-west-2}"
AWS_ACCOUNT_ID="${2:-$(aws sts get-caller-identity --query Account --output text)}"

# Project Configuration
PROJECT_NAME="cloud-custodian-stepfunction"
STACK_NAME="cloud-custodian-ec2-public-remediation"
LAMBDA_RUNTIME="python3.9"
LAMBDA_TIMEOUT=300
LAMBDA_MEMORY=512

# Resource Names
STEP_FUNCTION_NAME="EC2PublicInstanceRemediation"
IAM_ROLE_NAME="cloud-custodian-stepfunction-role"
LAMBDA_ROLE_NAME="cloud-custodian-lambda-role"
SNS_TOPIC_NAME="cloud-custodian-security-alerts"
DYNAMODB_TABLE_NAME="cloud-custodian-review-decisions"
DYNAMODB_APPROVALS_TABLE="cloud-custodian-approvals"

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEPFUNCTION_DIR="$SCRIPT_DIR/../stepfunction"
LAMBDA_DIR="$STEPFUNCTION_DIR/lambda-functions"
TEMP_DIR="/tmp/cloud-custodian-stepfunction-$$"
DEPLOY_DIR="$TEMP_DIR/deploy"

# Lambda Functions Configuration
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
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        log "ERROR" "jq is not installed"
        exit 1
    fi
    
    # Check zip
    if ! command -v zip &> /dev/null; then
        log "ERROR" "zip utility is not installed"
        exit 1
    fi
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        log "ERROR" "Python 3 is not installed"
        exit 1
    fi
    
    # Check Cloud Custodian
    if ! command -v custodian &> /dev/null; then
        log "WARN" "Cloud Custodian not found in PATH, attempting to install..."
        pip3 install c7n || {
            log "ERROR" "Failed to install Cloud Custodian"
            exit 1
        }
    fi
    
    log "INFO" "All prerequisites satisfied"
}

setup_directories() {
    log "STEP" "Setting up deployment directories..."
    
    # Create temporary directories
    mkdir -p "$TEMP_DIR"
    mkdir -p "$DEPLOY_DIR"
    mkdir -p "$DEPLOY_DIR/lambda-packages"
    
    log "INFO" "Deployment directory: $DEPLOY_DIR"
}

cleanup_on_exit() {
    log "INFO" "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
}

# Register cleanup function
trap cleanup_on_exit EXIT

# ==============================================================================
# IAM Role Creation Functions
# ==============================================================================

create_iam_roles() {
    log "STEP" "Creating IAM roles..."
    
    # Create Cloud Custodian Step Function role
    create_stepfunction_role
    
    # Create Lambda execution role
    create_lambda_role
    
    log "INFO" "IAM roles created successfully"
}

create_stepfunction_role() {
    log "INFO" "Creating Step Function IAM role..."
    
    # Trust policy for Cloud Custodian and Step Functions
    cat > "$TEMP_DIR/stepfunction-trust-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": [
                    "lambda.amazonaws.com",
                    "states.amazonaws.com",
                    "events.amazonaws.com"
                ]
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create role
    if aws iam get-role --role-name "$IAM_ROLE_NAME" &> /dev/null; then
        log "INFO" "Role $IAM_ROLE_NAME already exists"
    else
        aws iam create-role \
            --role-name "$IAM_ROLE_NAME" \
            --assume-role-policy-document "file://$TEMP_DIR/stepfunction-trust-policy.json" \
            --description "Cloud Custodian Step Function execution role"
        
        log "INFO" "Created IAM role: $IAM_ROLE_NAME"
    fi
    
    # Attach policies
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess"
    
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
    
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/CloudWatchEventsFullAccess"
    
    # Create custom policy for additional permissions
    cat > "$TEMP_DIR/stepfunction-custom-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "lambda:InvokeFunction",
                "sns:Publish",
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:UpdateItem",
                "dynamodb:DeleteItem",
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Create and attach custom policy
    aws iam put-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-name "CloudCustodianStepFunctionPolicy" \
        --policy-document "file://$TEMP_DIR/stepfunction-custom-policy.json"
    
    log "INFO" "Attached policies to $IAM_ROLE_NAME"
}

create_lambda_role() {
    log "INFO" "Creating Lambda execution IAM role..."
    
    # Trust policy for Lambda
    cat > "$TEMP_DIR/lambda-trust-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create role
    if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &> /dev/null; then
        log "INFO" "Role $LAMBDA_ROLE_NAME already exists"
    else
        aws iam create-role \
            --role-name "$LAMBDA_ROLE_NAME" \
            --assume-role-policy-document "file://$TEMP_DIR/lambda-trust-policy.json" \
            --description "Cloud Custodian Lambda execution role"
        
        log "INFO" "Created IAM role: $LAMBDA_ROLE_NAME"
    fi
    
    # Attach AWS managed policies
    aws iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    
    aws iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
    
    aws iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/CloudWatchFullAccess"
    
    aws iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonSNSFullAccess"
    
    aws iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
    
    log "INFO" "Attached policies to $LAMBDA_ROLE_NAME"
}

# ==============================================================================
# Supporting Resources Creation Functions
# ==============================================================================

create_supporting_resources() {
    log "STEP" "Creating supporting AWS resources..."
    
    # Create SNS topic
    create_sns_topic
    
    # Create DynamoDB tables
    create_dynamodb_tables
    
    log "INFO" "Supporting resources created successfully"
}

create_sns_topic() {
    log "INFO" "Creating SNS topic for notifications..."
    
    # Check if topic exists
    if aws sns get-topic-attributes --topic-arn "arn:aws:sns:$AWS_REGION:$AWS_ACCOUNT_ID:$SNS_TOPIC_NAME" &> /dev/null; then
        log "INFO" "SNS topic $SNS_TOPIC_NAME already exists"
    else
        aws sns create-topic --name "$SNS_TOPIC_NAME" --region "$AWS_REGION"
        log "INFO" "Created SNS topic: $SNS_TOPIC_NAME"
    fi
}

create_dynamodb_tables() {
    log "INFO" "Creating DynamoDB tables..."
    
    # Create review decisions table
    if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE_NAME" --region "$AWS_REGION" &> /dev/null; then
        log "INFO" "DynamoDB table $DYNAMODB_TABLE_NAME already exists"
    else
        aws dynamodb create-table \
            --table-name "$DYNAMODB_TABLE_NAME" \
            --attribute-definitions \
                AttributeName=instance_id,AttributeType=S \
                AttributeName=account_id,AttributeType=S \
            --key-schema \
                AttributeName=instance_id,KeyType=HASH \
                AttributeName=account_id,KeyType=RANGE \
            --billing-mode PAY_PER_REQUEST \
            --region "$AWS_REGION"
        
        # Wait for table to be active
        aws dynamodb wait table-exists --table-name "$DYNAMODB_TABLE_NAME" --region "$AWS_REGION"
        log "INFO" "Created DynamoDB table: $DYNAMODB_TABLE_NAME"
    fi
    
    # Create approvals table
    if aws dynamodb describe-table --table-name "$DYNAMODB_APPROVALS_TABLE" --region "$AWS_REGION" &> /dev/null; then
        log "INFO" "DynamoDB table $DYNAMODB_APPROVALS_TABLE already exists"
    else
        aws dynamodb create-table \
            --table-name "$DYNAMODB_APPROVALS_TABLE" \
            --attribute-definitions \
                AttributeName=instance_id,AttributeType=S \
                AttributeName=account_id,AttributeType=S \
            --key-schema \
                AttributeName=instance_id,KeyType=HASH \
                AttributeName=account_id,KeyType=RANGE \
            --billing-mode PAY_PER_REQUEST \
            --region "$AWS_REGION"
        
        # Wait for table to be active
        aws dynamodb wait table-exists --table-name "$DYNAMODB_APPROVALS_TABLE" --region "$AWS_REGION"
        log "INFO" "Created DynamoDB table: $DYNAMODB_APPROVALS_TABLE"
    fi
}

# ==============================================================================
# Lambda Functions Deployment
# ==============================================================================

deploy_lambda_functions() {
    log "STEP" "Deploying Lambda functions..."
    
    # Wait for IAM role to be available
    log "INFO" "Waiting for IAM role propagation..."
    sleep 30
    
    local lambda_role_arn="arn:aws:iam::$AWS_ACCOUNT_ID:role/$LAMBDA_ROLE_NAME"
    
    for function_name in "${!LAMBDA_FUNCTIONS[@]}"; do
        local source_file="${LAMBDA_FUNCTIONS[$function_name]}"
        deploy_single_lambda "$function_name" "$source_file" "$lambda_role_arn"
    done
    
    log "INFO" "All Lambda functions deployed successfully"
}

deploy_single_lambda() {
    local function_name="$1"
    local source_file="$2"
    local role_arn="$3"
    
    log "INFO" "Deploying Lambda function: $function_name"
    
    # Create deployment package
    local package_dir="$DEPLOY_DIR/lambda-packages/$function_name"
    local zip_file="$package_dir/$function_name.zip"
    
    mkdir -p "$package_dir"
    
    # Copy source file
    cp "$LAMBDA_DIR/$source_file" "$package_dir/lambda_function.py"
    
    # Create deployment package
    cd "$package_dir"
    zip -q "$zip_file" lambda_function.py
    
    # Deploy or update function
    if aws lambda get-function --function-name "$function_name" --region "$AWS_REGION" &> /dev/null; then
        log "INFO" "Updating existing function: $function_name"
        aws lambda update-function-code \
            --function-name "$function_name" \
            --zip-file "fileb://$zip_file" \
            --region "$AWS_REGION"
        
        aws lambda update-function-configuration \
            --function-name "$function_name" \
            --timeout "$LAMBDA_TIMEOUT" \
            --memory-size "$LAMBDA_MEMORY" \
            --region "$AWS_REGION"
    else
        log "INFO" "Creating new function: $function_name"
        aws lambda create-function \
            --function-name "$function_name" \
            --runtime "$LAMBDA_RUNTIME" \
            --role "$role_arn" \
            --handler "lambda_function.lambda_handler" \
            --code "fileb://$zip_file" \
            --timeout "$LAMBDA_TIMEOUT" \
            --memory-size "$LAMBDA_MEMORY" \
            --region "$AWS_REGION" \
            --description "Cloud Custodian Step Function - $function_name"
    fi
    
    # Add tags
    aws lambda tag-resource \
        --resource "arn:aws:lambda:$AWS_REGION:$AWS_ACCOUNT_ID:function:$function_name" \
        --tags "CreatedBy=cloud-custodian-stepfunction,Project=$PROJECT_NAME,Environment=production" \
        --region "$AWS_REGION"
    
    log "INFO" "Successfully deployed: $function_name"
}

# ==============================================================================
# Step Function Creation
# ==============================================================================

create_step_function() {
    log "STEP" "Creating Step Function..."
    
    # Update Step Function definition with actual ARNs
    local state_machine_def="$TEMP_DIR/state-machine-definition.json"
    local stepfunction_role_arn="arn:aws:iam::$AWS_ACCOUNT_ID:role/$IAM_ROLE_NAME"
    
    # Read and update the state machine definition
    sed "s/{region}/$AWS_REGION/g; s/{account_id}/$AWS_ACCOUNT_ID/g" \
        "$STEPFUNCTION_DIR/ec2-public-remediation-statemachine.json" > "$state_machine_def"
    
    # Create or update Step Function
    if aws stepfunctions describe-state-machine \
        --state-machine-arn "arn:aws:states:$AWS_REGION:$AWS_ACCOUNT_ID:stateMachine:$STEP_FUNCTION_NAME" \
        --region "$AWS_REGION" &> /dev/null; then
        
        log "INFO" "Updating existing Step Function: $STEP_FUNCTION_NAME"
        aws stepfunctions update-state-machine \
            --state-machine-arn "arn:aws:states:$AWS_REGION:$AWS_ACCOUNT_ID:stateMachine:$STEP_FUNCTION_NAME" \
            --definition "file://$state_machine_def" \
            --region "$AWS_REGION"
    else
        log "INFO" "Creating new Step Function: $STEP_FUNCTION_NAME"
        aws stepfunctions create-state-machine \
            --name "$STEP_FUNCTION_NAME" \
            --definition "file://$state_machine_def" \
            --role-arn "$stepfunction_role_arn" \
            --region "$AWS_REGION"
    fi
    
    log "INFO" "Step Function created/updated successfully"
}

# ==============================================================================
# Cloud Custodian Policy Deployment
# ==============================================================================

deploy_custodian_policies() {
    log "STEP" "Deploying Cloud Custodian policies..."
    
    # Update policy file with actual account ID and region
    local policy_file="$TEMP_DIR/ec2-public-stepfunction.yml"
    
    sed "s/{account_id}/$AWS_ACCOUNT_ID/g; s/{region}/$AWS_REGION/g" \
        "$STEPFUNCTION_DIR/../policies/ec2-public-stepfunction.yml" > "$policy_file"
    
    # Deploy policies
    log "INFO" "Deploying Cloud Custodian policies..."
    custodian run \
        --output-dir "$TEMP_DIR/custodian-output" \
        --region "$AWS_REGION" \
        "$policy_file"
    
    log "INFO" "Cloud Custodian policies deployed successfully"
}

# ==============================================================================
# Verification Functions
# ==============================================================================

verify_deployment() {
    log "STEP" "Verifying deployment..."
    
    local verification_passed=true
    
    # Check IAM roles
    if aws iam get-role --role-name "$IAM_ROLE_NAME" &> /dev/null; then
        log "INFO" "✓ IAM role verified: $IAM_ROLE_NAME"
    else
        log "ERROR" "✗ IAM role missing: $IAM_ROLE_NAME"
        verification_passed=false
    fi
    
    if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &> /dev/null; then
        log "INFO" "✓ Lambda role verified: $LAMBDA_ROLE_NAME"
    else
        log "ERROR" "✗ Lambda role missing: $LAMBDA_ROLE_NAME"
        verification_passed=false
    fi
    
    # Check Lambda functions
    for function_name in "${!LAMBDA_FUNCTIONS[@]}"; do
        if aws lambda get-function --function-name "$function_name" --region "$AWS_REGION" &> /dev/null; then
            log "INFO" "✓ Lambda function verified: $function_name"
        else
            log "ERROR" "✗ Lambda function missing: $function_name"
            verification_passed=false
        fi
    done
    
    # Check Step Function
    if aws stepfunctions describe-state-machine \
        --state-machine-arn "arn:aws:states:$AWS_REGION:$AWS_ACCOUNT_ID:stateMachine:$STEP_FUNCTION_NAME" \
        --region "$AWS_REGION" &> /dev/null; then
        log "INFO" "✓ Step Function verified: $STEP_FUNCTION_NAME"
    else
        log "ERROR" "✗ Step Function missing: $STEP_FUNCTION_NAME"
        verification_passed=false
    fi
    
    # Check supporting resources
    if aws sns get-topic-attributes \
        --topic-arn "arn:aws:sns:$AWS_REGION:$AWS_ACCOUNT_ID:$SNS_TOPIC_NAME" &> /dev/null; then
        log "INFO" "✓ SNS topic verified: $SNS_TOPIC_NAME"
    else
        log "ERROR" "✗ SNS topic missing: $SNS_TOPIC_NAME"
        verification_passed=false
    fi
    
    if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE_NAME" --region "$AWS_REGION" &> /dev/null; then
        log "INFO" "✓ DynamoDB table verified: $DYNAMODB_TABLE_NAME"
    else
        log "ERROR" "✗ DynamoDB table missing: $DYNAMODB_TABLE_NAME"
        verification_passed=false
    fi
    
    if $verification_passed; then
        log "INFO" "🎉 Deployment verification PASSED"
        return 0
    else
        log "ERROR" "❌ Deployment verification FAILED"
        return 1
    fi
}

# ==============================================================================
# Main Deployment Function
# ==============================================================================

main() {
    log "INFO" "Starting $SCRIPT_NAME v$SCRIPT_VERSION"
    log "INFO" "AWS Region: $AWS_REGION"
    log "INFO" "AWS Account: $AWS_ACCOUNT_ID"
    log "INFO" "Step Function: $STEP_FUNCTION_NAME"
    
    # Pre-deployment checks
    check_prerequisites
    setup_directories
    
    # Main deployment steps
    create_iam_roles
    create_supporting_resources
    deploy_lambda_functions
    create_step_function
    deploy_custodian_policies
    
    # Post-deployment verification
    if verify_deployment; then
        local end_time=$(date +%s)
        local duration=$((end_time - START_TIME))
        
        log "INFO" "🎉 Deployment completed successfully in ${duration} seconds!"
        
        # Display deployment summary
        cat << EOF

📊 DEPLOYMENT SUMMARY
═══════════════════════════════════════════════════════════════
Project: $PROJECT_NAME
Region: $AWS_REGION
Account: $AWS_ACCOUNT_ID

🔧 Created Resources:
─────────────────────────────────────────────────────────────
• Step Function: $STEP_FUNCTION_NAME
• IAM Roles: $IAM_ROLE_NAME, $LAMBDA_ROLE_NAME
• Lambda Functions: ${#LAMBDA_FUNCTIONS[@]} functions
• SNS Topic: $SNS_TOPIC_NAME
• DynamoDB Tables: $DYNAMODB_TABLE_NAME, $DYNAMODB_APPROVALS_TABLE
• Cloud Custodian Policies: ec2-public-stepfunction

🚀 Next Steps:
─────────────────────────────────────────────────────────────
1. Test the deployment with: ./test-stepfunction-demo.sh
2. Launch a public EC2 instance to trigger the workflow
3. Monitor Step Function executions in AWS Console
4. Check CloudWatch Logs for detailed execution logs

📚 Resources:
─────────────────────────────────────────────────────────────
• Step Function ARN: arn:aws:states:$AWS_REGION:$AWS_ACCOUNT_ID:stateMachine:$STEP_FUNCTION_NAME
• Console URL: https://$AWS_REGION.console.aws.amazon.com/states/home?region=$AWS_REGION#/statemachines/view/arn:aws:states:$AWS_REGION:$AWS_ACCOUNT_ID:stateMachine:$STEP_FUNCTION_NAME

⚠️  Cleanup:
─────────────────────────────────────────────────────────────
To remove all resources: ./cleanup-stepfunction-demo.sh

═══════════════════════════════════════════════════════════════
EOF
    else
        log "ERROR" "Deployment failed verification. Check the logs above."
        exit 1
    fi
}

# Run main function
main "$@"