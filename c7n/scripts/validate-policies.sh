#!/bin/bash

# validate-policies.sh - Validate Cloud Custodian policies before deployment
# Usage: ./validate-policies.sh [-a account] [-r region] [-p policy_file] [-v]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ACCOUNT=""
REGION="us-east-1"
POLICY_FILE=""
VERBOSE=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

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
Usage: $0 [-a account] [-r region] [-p policy_file] [-v] [-h]

Options:
    -a account      Target AWS account (optional, uses default if not specified)
    -r region       AWS region (default: us-east-1)
    -p policy_file  Specific policy file to validate (optional, validates all if not specified)
    -v              Verbose output
    -h              Show this help message

Examples:
    $0                                    # Validate all policies with default settings
    $0 -a development -r us-west-2        # Validate for specific account and region
    $0 -p policies/user-security.yml -v   # Validate specific policy with verbose output
    
EOF
}

# Parse command line arguments
while getopts "a:r:p:vh" opt; do
    case $opt in
        a)
            ACCOUNT="$OPTARG"
            ;;
        r)
            REGION="$OPTARG"
            ;;
        p)
            POLICY_FILE="$OPTARG"
            ;;
        v)
            VERBOSE=true
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

# Validation functions
validate_environment() {
    print_status "Validating environment..."
    
    # Check if custodian command is available
    if ! command -v custodian &> /dev/null; then
        print_error "Cloud Custodian (custodian) command not found. Please install it first:"
        echo "  pip install c7n"
        exit 1
    fi
    
    # Check if AWS CLI is available
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI not found. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured or invalid."
        exit 1
    fi
    
    print_success "Environment validation passed"
}

validate_policy_syntax() {
    local policy_file="$1"
    
    print_status "Validating syntax for: $policy_file"
    
    # Check YAML syntax
    if ! python3 -c "import yaml; yaml.safe_load(open('$policy_file'))" 2>/dev/null; then
        print_error "Invalid YAML syntax in $policy_file"
        return 1
    fi
    
    # Check Cloud Custodian policy structure
    if ! custodian validate "$policy_file" 2>/dev/null; then
        print_error "Cloud Custodian validation failed for $policy_file"
        if [ "$VERBOSE" = true ]; then
            custodian validate "$policy_file"
        fi
        return 1
    fi
    
    print_success "Syntax validation passed for $policy_file"
    return 0
}

validate_policy_schema() {
    local policy_file="$1"
    
    print_status "Validating schema for: $policy_file"
    
    # Run schema validation with detailed output
    local validation_output
    validation_output=$(custodian schema --json 2>&1)
    
    if [ $? -ne 0 ]; then
        print_error "Schema validation failed for $policy_file"
        if [ "$VERBOSE" = true ]; then
            echo "$validation_output"
        fi
        return 1
    fi
    
    print_success "Schema validation passed for $policy_file"
    return 0
}

dry_run_policy() {
    local policy_file="$1"
    
    print_status "Running dry-run for: $policy_file"
    
    # Create temporary output directory
    local temp_dir=$(mktemp -d)
    local dry_run_args="--dryrun -s $temp_dir"
    
    if [ -n "$REGION" ]; then
        dry_run_args="$dry_run_args --region $REGION"
    fi
    
    # Run dry-run
    if custodian run $dry_run_args "$policy_file" &> /dev/null; then
        print_success "Dry-run passed for $policy_file"
        
        # Show resource counts if verbose
        if [ "$VERBOSE" = true ] && [ -d "$temp_dir" ]; then
            print_status "Resource summary:"
            find "$temp_dir" -name "resources.json" -exec wc -l {} \; 2>/dev/null | while read count file; do
                policy_name=$(basename "$(dirname "$file")")
                if [ "$count" -gt 1 ]; then  # Subtract 1 for JSON array brackets
                    echo "  $policy_name: $((count-2)) resources found"
                fi
            done
        fi
    else
        print_error "Dry-run failed for $policy_file"
        if [ "$VERBOSE" = true ]; then
            custodian run $dry_run_args "$policy_file"
        fi
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Cleanup
    rm -rf "$temp_dir"
    return 0
}

# Main validation logic
main() {
    print_status "Starting Cloud Custodian policy validation..."
    print_status "Region: $REGION"
    if [ -n "$ACCOUNT" ]; then
        print_status "Account: $ACCOUNT"
    fi
    echo ""
    
    # Validate environment
    validate_environment
    
    # Determine which policies to validate
    local policies_to_validate=()
    
    if [ -n "$POLICY_FILE" ]; then
        if [ ! -f "$POLICY_FILE" ]; then
            print_error "Policy file not found: $POLICY_FILE"
            exit 1
        fi
        policies_to_validate+=("$POLICY_FILE")
    else
        # Find all policy files
        while IFS= read -r -d '' file; do
            policies_to_validate+=("$file")
        done < <(find "$PROJECT_ROOT/policies" -name "*.yml" -o -name "*.yaml" -print0 2>/dev/null)
        
        if [ ${#policies_to_validate[@]} -eq 0 ]; then
            print_error "No policy files found in $PROJECT_ROOT/policies"
            exit 1
        fi
    fi
    
    print_status "Found ${#policies_to_validate[@]} policy file(s) to validate"
    echo ""
    
    # Validation counters
    local total_files=0
    local passed_files=0
    local failed_files=0
    
    # Validate each policy file
    for policy_file in "${policies_to_validate[@]}"; do
        echo "=========================================="
        print_status "Validating: $(basename "$policy_file")"
        echo "=========================================="
        
        local file_passed=true
        total_files=$((total_files + 1))
        
        # Syntax validation
        if ! validate_policy_syntax "$policy_file"; then
            file_passed=false
        fi
        
        # Schema validation
        if [ "$file_passed" = true ] && ! validate_policy_schema "$policy_file"; then
            file_passed=false
        fi
        
        # Dry-run validation
        if [ "$file_passed" = true ] && ! dry_run_policy "$policy_file"; then
            file_passed=false
        fi
        
        if [ "$file_passed" = true ]; then
            passed_files=$((passed_files + 1))
            print_success "✅ All validations passed for $(basename "$policy_file")"
        else
            failed_files=$((failed_files + 1))
            print_error "❌ Validation failed for $(basename "$policy_file")"
        fi
        
        echo ""
    done
    
    # Final summary
    echo "=========================================="
    print_status "VALIDATION SUMMARY"
    echo "=========================================="
    echo "Total files: $total_files"
    echo "Passed: $passed_files"
    echo "Failed: $failed_files"
    echo ""
    
    if [ $failed_files -eq 0 ]; then
        print_success "🎉 All policy validations passed!"
        echo ""
        print_status "Your policies are ready for deployment. You can now:"
        echo "  1. Deploy updated policies: ./deploy-updated-policies.sh"
        echo "  2. Deploy all policies: ./deploy-policies.sh"
        echo "  3. Use GitHub Actions workflow for automated deployment"
        exit 0
    else
        print_error "❌ $failed_files policy file(s) failed validation"
        echo ""
        print_warning "Please fix the validation errors before deploying."
        print_warning "Use -v flag for verbose output to see detailed error messages."
        exit 1
    fi
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi