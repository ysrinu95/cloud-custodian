#!/bin/bash

# Cloud Custodian GuardDuty Security Demo - CI/CD Pipeline Script
# This script is designed to run in various CI/CD environments
# Supports: GitHub Actions, GitLab CI, Jenkins, Azure DevOps, AWS CodeBuild

set -e

# Pipeline Environment Detection
detect_pipeline_environment() {
    if [[ -n "$GITHUB_ACTIONS" ]]; then
        echo "github-actions"
    elif [[ -n "$GITLAB_CI" ]]; then
        echo "gitlab-ci"
    elif [[ -n "$JENKINS_URL" ]]; then
        echo "jenkins"
    elif [[ -n "$TF_BUILD" ]]; then
        echo "azure-devops"
    elif [[ -n "$CODEBUILD_BUILD_ID" ]]; then
        echo "aws-codebuild"
    else
        echo "unknown"
    fi
}

# Logging functions adapted for different CI/CD systems
setup_logging() {
    local pipeline_env="$1"
    
    case "$pipeline_env" in
        "github-actions")
            log_info() { echo "::notice::$1"; }
            log_warning() { echo "::warning::$1"; }
            log_error() { echo "::error::$1"; }
            log_success() { echo "::notice::✅ $1"; }
            ;;
        "gitlab-ci")
            log_info() { echo -e "\e[36m[INFO]\e[0m $1"; }
            log_warning() { echo -e "\e[33m[WARNING]\e[0m $1"; }
            log_error() { echo -e "\e[31m[ERROR]\e[0m $1"; }
            log_success() { echo -e "\e[32m[SUCCESS]\e[0m $1"; }
            ;;
        "azure-devops")
            log_info() { echo "##[command]$1"; }
            log_warning() { echo "##[warning]$1"; }
            log_error() { echo "##[error]$1"; }
            log_success() { echo "##[section]✅ $1"; }
            ;;
        *)
            log_info() { echo "[INFO] $1"; }
            log_warning() { echo "[WARNING] $1"; }
            log_error() { echo "[ERROR] $1"; }
            log_success() { echo "[SUCCESS] ✅ $1"; }
            ;;
    esac
}

# Configuration with environment variable support
PIPELINE_ENV=$(detect_pipeline_environment)
setup_logging "$PIPELINE_ENV"

# Configuration
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
DEMO_PREFIX="custodian-guardduty-pipeline"
DEMO_TAG_KEY="CustodianPipelineDemo"
DEMO_TAG_VALUE="GuardDutySecurityTest"
MONITORING_DURATION="${MONITORING_DURATION:-10}"  # Shorter for CI/CD
RUN_MODE="${RUN_MODE:-demo}"  # demo, check, cleanup
DRY_RUN="${DRY_RUN:-false}"

# Pipeline-specific configuration
case "$PIPELINE_ENV" in
    "github-actions")
        BUILD_ID="${GITHUB_RUN_ID:-unknown}"
        BRANCH="${GITHUB_REF_NAME:-main}"
        ;;
    "gitlab-ci")
        BUILD_ID="${CI_PIPELINE_ID:-unknown}"
        BRANCH="${CI_COMMIT_REF_NAME:-main}"
        ;;
    "jenkins")
        BUILD_ID="${BUILD_NUMBER:-unknown}"
        BRANCH="${GIT_BRANCH:-main}"
        ;;
    "azure-devops")
        BUILD_ID="${BUILD_BUILDID:-unknown}"
        BRANCH="${BUILD_SOURCEBRANCHNAME:-main}"
        ;;
    "aws-codebuild")
        BUILD_ID="${CODEBUILD_BUILD_NUMBER:-unknown}"
        BRANCH="${CODEBUILD_SOURCE_REPO_URL##*/}"
        ;;
    *)
        BUILD_ID="unknown"
        BRANCH="main"
        ;;
esac

# Enhanced demo tag with pipeline info
DEMO_TAG_VALUE="GuardDutyTest-${PIPELINE_ENV}-${BUILD_ID}"

log_info "🔧 Pipeline Environment: $PIPELINE_ENV"
log_info "🏗️ Build ID: $BUILD_ID"
log_info "🌿 Branch: $BRANCH"
log_info "🌍 Region: $REGION"
log_info "⏱️ Monitoring Duration: $MONITORING_DURATION minutes"
log_info "🎯 Run Mode: $RUN_MODE"

# Pre-flight checks
preflight_checks() {
    log_info "🔍 Running pre-flight checks..."
    
    # Check AWS CLI
    if ! command -v aws >/dev/null 2>&1; then
        log_error "AWS CLI is not installed"
        return 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured or invalid"
        return 1
    fi
    
    # Check required permissions (basic check)
    local account_id=$(aws sts get-caller-identity --query 'Account' --output text)
    local user_arn=$(aws sts get-caller-identity --query 'Arn' --output text)
    
    log_info "✅ AWS Account: $account_id"
    log_info "✅ AWS User/Role: $user_arn"
    
    # Check if GuardDuty is available in region
    aws guardduty list-detectors --region "$REGION" >/dev/null 2>&1 || {
        log_error "Cannot access GuardDuty in region $REGION"
        return 1
    }
    
    log_success "Pre-flight checks passed"
}

# Lightweight resource creation for CI/CD
create_minimal_vulnerable_resources() {
    log_info "🏗️ Creating minimal vulnerable resources for pipeline demo..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would create vulnerable security group and instance"
        echo "sg-dryrun123,i-dryrun456,3.3.3.3"
        return 0
    fi
    
    # Get default VPC (fail fast if not available)
    local vpc_id=$(aws ec2 describe-vpcs \
        --region "$REGION" \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' \
        --output text 2>/dev/null || echo "None")
    
    if [[ "$vpc_id" == "None" ]]; then
        log_error "No default VPC found - creating VPC is beyond pipeline scope"
        return 1
    fi
    
    # Create minimal security group with timestamp to avoid conflicts
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local sg_name="$DEMO_PREFIX-sg-$timestamp"
    
    log_info "Creating security group: $sg_name"
    local sg_id=$(aws ec2 create-security-group \
        --region "$REGION" \
        --group-name "$sg_name" \
        --description "Pipeline demo security group - $PIPELINE_ENV build $BUILD_ID" \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=$DEMO_TAG_KEY,Value=$DEMO_TAG_VALUE},{Key=Pipeline,Value=$PIPELINE_ENV},{Key=BuildId,Value=$BUILD_ID}]" \
        --query 'GroupId' \
        --output text)
    
    # Add only SSH rule (minimal for demo)
    aws ec2 authorize-security-group-ingress \
        --region "$REGION" \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0 >/dev/null || true
    
    log_success "Created security group: $sg_id"
    
    # For CI/CD, we might skip EC2 instance creation to save time/cost
    if [[ "${SKIP_EC2_CREATION:-false}" == "true" ]]; then
        log_info "Skipping EC2 instance creation (SKIP_EC2_CREATION=true)"
        echo "$sg_id,none,none"
        return 0
    fi
    
    # Create minimal EC2 instance
    local ami_id=$(aws ec2 describe-images \
        --region "$REGION" \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=state,Values=available" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    
    local subnet_id=$(aws ec2 describe-subnets \
        --region "$REGION" \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=map-public-ip-on-launch,Values=true" \
        --query 'Subnets[0].SubnetId' \
        --output text)
    
    if [[ "$subnet_id" == "None" ]]; then
        log_warning "No public subnet found, using first available subnet"
        subnet_id=$(aws ec2 describe-subnets \
            --region "$REGION" \
            --filters "Name=vpc-id,Values=$vpc_id" \
            --query 'Subnets[0].SubnetId' \
            --output text)
    fi
    
    # Simple user data for pipeline demo
    cat > /tmp/pipeline-user-data.sh << 'EOF'
#!/bin/bash
yum update -y
echo "Pipeline GuardDuty demo instance started at $(date)" > /var/log/pipeline-demo.log
# Minimal suspicious activity for quick detection
nslookup pool.minergate.com 8.8.8.8 >/dev/null 2>&1 || true
EOF
    
    log_info "Launching EC2 instance..."
    local instance_id=$(aws ec2 run-instances \
        --region "$REGION" \
        --image-id "$ami_id" \
        --count 1 \
        --instance-type t3.nano \
        --security-group-ids "$sg_id" \
        --subnet-id "$subnet_id" \
        --user-data file:///tmp/pipeline-user-data.sh \
        --tag-specifications "ResourceType=instance,Tags=[{Key=$DEMO_TAG_KEY,Value=$DEMO_TAG_VALUE},{Key=Pipeline,Value=$PIPELINE_ENV},{Key=BuildId,Value=$BUILD_ID},{Key=Name,Value=$DEMO_PREFIX-instance}]" \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    # Don't wait for running state in pipeline (faster)
    local public_ip="pending"
    
    log_success "Created EC2 instance: $instance_id"
    
    # Cleanup temp file
    rm -f /tmp/pipeline-user-data.sh
    
    echo "$sg_id,$instance_id,$public_ip"
}

# Quick cleanup for pipeline
pipeline_cleanup() {
    log_info "🧹 Starting pipeline cleanup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would clean up demo resources"
        return 0
    fi
    
    # Terminate instances
    local instances=$(aws ec2 describe-instances \
        --region "$REGION" \
        --filters "Name=tag:$DEMO_TAG_KEY,Values=$DEMO_TAG_VALUE" "Name=instance-state-name,Values=running,pending,stopped" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$instances" && "$instances" != "None" ]]; then
        log_info "Terminating instances: $instances"
        aws ec2 terminate-instances --region "$REGION" --instance-ids $instances >/dev/null || true
        
        # For pipeline, don't wait for termination completion
        log_info "Instance termination initiated (not waiting for completion)"
    fi
    
    # Delete security groups
    local security_groups=$(aws ec2 describe-security-groups \
        --region "$REGION" \
        --filters "Name=tag:$DEMO_TAG_KEY,Values=$DEMO_TAG_VALUE" \
        --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$security_groups" && "$security_groups" != "None" ]]; then
        log_info "Deleting security groups: $security_groups"
        for sg in $security_groups; do
            # Retry deletion as instances may still be terminating
            for i in {1..3}; do
                aws ec2 delete-security-group --region "$REGION" --group-id "$sg" 2>/dev/null && break
                log_info "Retry $i/3: Waiting for dependencies to clear..."
                sleep 10
            done
        done
    fi
    
    log_success "Pipeline cleanup completed"
}

# Quick GuardDuty check
check_guardduty() {
    log_info "🔍 Checking GuardDuty status..."
    
    local detector_id=$(aws guardduty list-detectors \
        --region "$REGION" \
        --query 'DetectorIds[0]' \
        --output text 2>/dev/null || echo "None")
    
    if [[ "$detector_id" == "None" || -z "$detector_id" ]]; then
        log_warning "GuardDuty is not enabled in region $REGION"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_warning "DRY RUN: Would enable GuardDuty"
            return 0
        fi
        
        log_info "Enabling GuardDuty..."
        detector_id=$(aws guardduty create-detector \
            --region "$REGION" \
            --enable \
            --query 'DetectorId' \
            --output text)
        
        log_success "GuardDuty enabled: $detector_id"
    else
        log_success "GuardDuty already enabled: $detector_id"
    fi
    
    # Quick findings check (last hour only)
    local recent_findings=$(aws guardduty list-findings \
        --region "$REGION" \
        --detector-id "$detector_id" \
        --finding-criteria "{\"updatedAt\":{\"gte\":$(($(date +%s) - 3600))000}}" \
        --query 'FindingIds' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$recent_findings" && "$recent_findings" != "None" ]]; then
        local finding_count=$(echo "$recent_findings" | wc -w)
        log_success "Found $finding_count recent GuardDuty findings"
    else
        log_info "No recent findings (normal for new setup)"
    fi
    
    echo "$detector_id"
}

# Pipeline-optimized monitoring (shorter duration)
monitor_findings_pipeline() {
    local detector_id="$1"
    local duration="$2"
    
    log_info "📊 Monitoring GuardDuty findings for $duration minutes (pipeline mode)..."
    
    local end_time=$(($(date +%s) + duration * 60))
    local check_interval=30  # Check every 30 seconds for pipeline
    
    while [[ $(date +%s) -lt $end_time ]]; do
        local findings=$(aws guardduty list-findings \
            --region "$REGION" \
            --detector-id "$detector_id" \
            --finding-criteria "{\"updatedAt\":{\"gte\":$(($(date +%s) - 1800))000}}" \
            --query 'FindingIds' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$findings" && "$findings" != "None" ]]; then
            local finding_count=$(echo "$findings" | wc -w)
            log_success "🚨 Found $finding_count findings in pipeline run!"
            
            # Show first finding details
            local first_finding=$(echo "$findings" | awk '{print $1}')
            if [[ -n "$first_finding" ]]; then
                aws guardduty get-findings \
                    --region "$REGION" \
                    --detector-id "$detector_id" \
                    --finding-ids "$first_finding" \
                    --query 'Findings[0].{Type:Type,Severity:Severity,Title:Title}' \
                    --output table 2>/dev/null || true
            fi
            break
        fi
        
        log_info "No new findings yet..."
        sleep $check_interval
    done
}

# Generate pipeline report
generate_pipeline_report() {
    local detector_id="$1"
    local sg_id="$2"
    local instance_id="$3"
    
    log_info "📋 Generating pipeline demo report..."
    
    cat << EOF > pipeline-demo-report.json
{
  "pipeline": {
    "environment": "$PIPELINE_ENV",
    "build_id": "$BUILD_ID",
    "branch": "$BRANCH",
    "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  },
  "aws": {
    "region": "$REGION",
    "guardduty_detector": "$detector_id",
    "security_group": "$sg_id",
    "instance": "$instance_id"
  },
  "demo": {
    "duration_minutes": $MONITORING_DURATION,
    "run_mode": "$RUN_MODE",
    "dry_run": $DRY_RUN
  },
  "status": "completed"
}
EOF
    
    log_success "Pipeline report generated: pipeline-demo-report.json"
}

# Main pipeline function
main() {
    log_info "🚀 Starting GuardDuty Security Demo Pipeline"
    log_info "Environment: $PIPELINE_ENV | Build: $BUILD_ID | Region: $REGION"
    
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
            --mode)
                RUN_MODE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                cat << EOF
Usage: $0 [OPTIONS]

GuardDuty Security Demo - CI/CD Pipeline Script

OPTIONS:
    --region REGION     AWS region (default: $REGION)
    --duration MINUTES  Monitoring duration (default: $MONITORING_DURATION)
    --mode MODE         Run mode: demo, check, cleanup (default: $RUN_MODE)
    --dry-run          Simulate actions without creating resources
    --help             Show this help

ENVIRONMENT VARIABLES:
    AWS_REGION         AWS region
    MONITORING_DURATION Duration in minutes
    RUN_MODE           demo, check, or cleanup
    DRY_RUN           true/false for dry run mode
    SKIP_EC2_CREATION true/false to skip EC2 instance creation

EXAMPLES:
    $0                         # Run demo with defaults
    $0 --mode check           # Only check GuardDuty status
    $0 --mode cleanup         # Only cleanup resources
    $0 --dry-run             # Simulate without creating resources

EOF
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Set trap for cleanup
    trap 'pipeline_cleanup || true' EXIT
    
    # Run pre-flight checks
    preflight_checks
    
    case "$RUN_MODE" in
        "check")
            log_info "🔍 Running check mode only..."
            detector_id=$(check_guardduty)
            log_success "Check completed - GuardDuty detector: $detector_id"
            ;;
        "cleanup")
            log_info "🧹 Running cleanup mode only..."
            pipeline_cleanup
            log_success "Cleanup completed"
            ;;
        "demo")
            log_info "🎯 Running full demo mode..."
            
            # Check/enable GuardDuty
            detector_id=$(check_guardduty)
            
            # Create minimal vulnerable resources
            result=$(create_minimal_vulnerable_resources)
            IFS=',' read -r sg_id instance_id public_ip <<< "$result"
            
            log_info "Created resources - SG: $sg_id, Instance: $instance_id"
            
            # Quick monitoring for pipeline
            monitor_findings_pipeline "$detector_id" "$MONITORING_DURATION"
            
            # Generate report
            generate_pipeline_report "$detector_id" "$sg_id" "$instance_id"
            
            log_success "🎯 Pipeline demo completed!"
            ;;
        *)
            log_error "Unknown run mode: $RUN_MODE"
            exit 1
            ;;
    esac
    
    log_success "✅ GuardDuty Security Demo Pipeline Completed"
    log_info "Environment: $PIPELINE_ENV | Status: Success | Mode: $RUN_MODE"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi