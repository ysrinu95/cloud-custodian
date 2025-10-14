#!/bin/bash

# cleanup-events-rule.sh - Standalone script to clean up CloudWatch Events rules with targets
# Usage: ./cleanup-events-rule.sh -r rule-name [-p profile] [-R region] [-d]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
RULE_NAME=""
PROFILE=""
REGION="us-east-1"
DRYRUN=false

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 -r rule-name [-p profile] [-R region] [-d] [-h]

Clean up CloudWatch Events rules that have targets attached.
This script first removes all targets, then deletes the rule.

Options:
    -r rule-name    Name of the CloudWatch Events rule to delete (required)
    -p profile      AWS CLI profile to use (optional)
    -R region       AWS region (default: us-east-1)
    -d              Dry run mode (show what would be done)
    -h              Show this help message

Examples:
    $0 -r custodian-ebs-unencrypted-volumes-scheduled
    $0 -r my-rule -p production -R us-west-2 -d
    
EOF
}

# Parse command line arguments
while getopts "r:p:R:dh" opt; do
    case $opt in
        r)
            RULE_NAME="$OPTARG"
            ;;
        p)
            PROFILE="$OPTARG"
            ;;
        R)
            REGION="$OPTARG"
            ;;
        d)
            DRYRUN=true
            ;;
        h)
            show_usage
            exit 0
            ;;
        \?)
            print_error "Invalid option: -$OPTARG"
            show_usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$RULE_NAME" ]; then
    print_error "Rule name is required (-r option)"
    show_usage
    exit 1
fi

# Build AWS CLI command prefix
AWS_CMD="aws events"
if [ -n "$PROFILE" ]; then
    AWS_CMD="$AWS_CMD --profile $PROFILE"
fi
AWS_CMD="$AWS_CMD --region $REGION"

# Function to check if rule exists
check_rule_exists() {
    local rule_name="$1"
    
    print_status "Checking if rule '$rule_name' exists..."
    
    if $AWS_CMD describe-rule --name "$rule_name" &>/dev/null; then
        print_success "Rule '$rule_name' found"
        return 0
    else
        print_warning "Rule '$rule_name' not found"
        return 1
    fi
}

# Function to list and remove targets
remove_targets() {
    local rule_name="$1"
    
    print_status "Listing targets for rule '$rule_name'..."
    
    # Get targets
    local targets_json
    targets_json=$($AWS_CMD list-targets-by-rule --rule "$rule_name" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        print_error "Failed to list targets for rule '$rule_name'"
        return 1
    fi
    
    # Extract target IDs
    local target_ids
    target_ids=$(echo "$targets_json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
targets = data.get('Targets', [])
if targets:
    print(' '.join([target['Id'] for target in targets]))
else:
    print('')
")
    
    if [ -z "$target_ids" ]; then
        print_status "No targets found for rule '$rule_name'"
        return 0
    fi
    
    print_status "Found targets: $target_ids"
    
    if [ "$DRYRUN" = true ]; then
        print_warning "DRYRUN: Would remove targets: $target_ids"
        return 0
    fi
    
    # Remove targets
    print_status "Removing targets from rule '$rule_name'..."
    
    local remove_result
    remove_result=$($AWS_CMD remove-targets --rule "$rule_name" --ids $target_ids 2>&1)
    
    if [ $? -eq 0 ]; then
        print_success "Successfully removed targets from rule '$rule_name'"
        
        # Check for failed entries
        local failed_count
        failed_count=$(echo "$remove_result" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('FailedEntryCount', 0))
except:
    print(0)
" 2>/dev/null)
        
        if [ "$failed_count" -gt 0 ]; then
            print_warning "Some targets failed to be removed (FailedEntryCount: $failed_count)"
            echo "$remove_result"
            return 1
        fi
        
        return 0
    else
        print_error "Failed to remove targets from rule '$rule_name'"
        echo "$remove_result"
        return 1
    fi
}

# Function to delete the rule
delete_rule() {
    local rule_name="$1"
    
    print_status "Deleting rule '$rule_name'..."
    
    if [ "$DRYRUN" = true ]; then
        print_warning "DRYRUN: Would delete rule '$rule_name'"
        return 0
    fi
    
    local delete_result
    delete_result=$($AWS_CMD delete-rule --name "$rule_name" 2>&1)
    
    if [ $? -eq 0 ]; then
        print_success "Successfully deleted rule '$rule_name'"
        return 0
    else
        print_error "Failed to delete rule '$rule_name'"
        echo "$delete_result"
        return 1
    fi
}

# Main execution
main() {
    print_status "Starting CloudWatch Events rule cleanup..."
    print_status "Rule: $RULE_NAME"
    print_status "Region: $REGION"
    if [ -n "$PROFILE" ]; then
        print_status "Profile: $PROFILE"
    fi
    if [ "$DRYRUN" = true ]; then
        print_warning "DRYRUN MODE: No changes will be made"
    fi
    echo ""
    
    # Check if AWS CLI is available
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI not found. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! $AWS_CMD describe-rule --name "non-existent-rule-test" &>/dev/null; then
        # This should fail with AccessDenied or similar, not with credential errors
        # If it fails with credential errors, we'll catch it here
        local test_result
        test_result=$($AWS_CMD describe-rule --name "non-existent-rule-test" 2>&1)
        if echo "$test_result" | grep -q -E "(credential|token|auth|access.*denied)" -i; then
            print_error "AWS credentials not configured or invalid"
            exit 1
        fi
    fi
    
    # Step 1: Check if rule exists
    if ! check_rule_exists "$RULE_NAME"; then
        print_warning "Rule '$RULE_NAME' does not exist. Nothing to clean up."
        exit 0
    fi
    
    # Step 2: Remove targets
    if ! remove_targets "$RULE_NAME"; then
        print_error "Failed to remove targets. Cannot proceed with rule deletion."
        exit 1
    fi
    
    # Wait a moment for targets to be fully removed
    if [ "$DRYRUN" = false ]; then
        print_status "Waiting for targets to be fully removed..."
        sleep 3
    fi
    
    # Step 3: Delete the rule
    if ! delete_rule "$RULE_NAME"; then
        print_error "Failed to delete rule '$RULE_NAME'"
        exit 1
    fi
    
    echo ""
    print_success "✅ CloudWatch Events rule cleanup completed successfully!"
    
    if [ "$DRYRUN" = false ]; then
        print_status "Rule '$RULE_NAME' has been completely removed"
    else
        print_status "DRYRUN completed - no actual changes were made"
    fi
}

# Run main function
main "$@"