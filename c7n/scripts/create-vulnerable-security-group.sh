#!/bin/bash

# Create REAL GuardDuty HIGH severity finding using EC2 Security Group
# Creates a vulnerable security group that GuardDuty will detect

set -e

REGION="${AWS_REGION:-us-east-1}"
DEMO_TAG="CustodianGuardDutyTest"
SG_NAME="custodian-guardduty-vulnerable-sg"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

cleanup() {
    if [[ -n "$SG_ID" && "$SG_ID" != "None" ]]; then
        log_info "🧹 Cleaning up security group: $SG_ID"
        aws ec2 delete-security-group --group-id "$SG_ID" --region "$REGION" 2>/dev/null || true
        log_success "Cleanup complete"
    fi
}

# Trap to cleanup on exit
trap cleanup EXIT INT TERM

echo ""
log_warning "⚠️  REAL GUARDDUTY HIGH SEVERITY FINDING GENERATOR"
log_info "Creating vulnerable EC2 Security Group with dangerous rules"
log_info "GuardDuty will detect this and create HIGH severity finding"
echo ""

# Get GuardDuty detector
DETECTOR_ID=$(aws guardduty list-detectors --region "$REGION" --query 'DetectorIds[0]' --output text 2>/dev/null || echo "None")

if [[ "$DETECTOR_ID" == "None" || -z "$DETECTOR_ID" ]]; then
    log_error "GuardDuty is not enabled in region $REGION"
    log_info "Enabling GuardDuty..."
    DETECTOR_ID=$(aws guardduty create-detector --region "$REGION" --enable --query 'DetectorId' --output text)
    log_success "GuardDuty enabled: $DETECTOR_ID"
fi

log_success "GuardDuty Detector: $DETECTOR_ID"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
log_info "Account: $ACCOUNT_ID"
log_info "Region: $REGION"
echo ""

# Get default VPC
log_info "🔍 Finding default VPC..."
VPC_ID=$(aws ec2 describe-vpcs \
    --region "$REGION" \
    --filters "Name=is-default,Values=true" \
    --query 'Vpcs[0].VpcId' \
    --output text 2>/dev/null || echo "None")

if [[ "$VPC_ID" == "None" || -z "$VPC_ID" ]]; then
    log_error "No default VPC found in region $REGION"
    exit 1
fi

log_success "Default VPC: $VPC_ID"
echo ""

# Create vulnerable security group
log_warning "🚨 Creating VULNERABLE security group..."
log_info "Security Group Name: $SG_NAME"
echo ""

SG_ID=$(aws ec2 create-security-group \
    --region "$REGION" \
    --group-name "$SG_NAME" \
    --description "VULNERABLE: Created by Cloud Custodian for GuardDuty testing - DELETE AFTER TEST" \
    --vpc-id "$VPC_ID" \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$SG_NAME},{Key=Purpose,Value=$DEMO_TAG},{Key=DeleteAfter,Value=1hour}]" \
    --query 'GroupId' \
    --output text 2>/dev/null)

if [[ -z "$SG_ID" || "$SG_ID" == "None" ]]; then
    log_error "Failed to create security group"
    exit 1
fi

log_success "Security Group Created: $SG_ID"
echo ""

# Add DANGEROUS rules that GuardDuty will detect
log_warning "⚠️  Adding DANGEROUS ingress rules (GuardDuty will flag these):"
echo ""

# Rule 1: SSH open to the world (0.0.0.0/0) - HIGH severity
log_info "  1. SSH (port 22) open to 0.0.0.0/0"
aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 \
    --group-rule-description "VULNERABLE: SSH open to internet" >/dev/null 2>&1

# Rule 2: RDP open to the world - HIGH severity
log_info "  2. RDP (port 3389) open to 0.0.0.0/0"
aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 3389 \
    --cidr 0.0.0.0/0 \
    --group-rule-description "VULNERABLE: RDP open to internet" >/dev/null 2>&1

# Rule 3: PostgreSQL open to the world - HIGH severity
log_info "  3. PostgreSQL (port 5432) open to 0.0.0.0/0"
aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 5432 \
    --cidr 0.0.0.0/0 \
    --group-rule-description "VULNERABLE: PostgreSQL open to internet" >/dev/null 2>&1

# Rule 4: MySQL open to the world - HIGH severity
log_info "  4. MySQL (port 3306) open to 0.0.0.0/0"
aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 3306 \
    --cidr 0.0.0.0/0 \
    --group-rule-description "VULNERABLE: MySQL open to internet" >/dev/null 2>&1

echo ""
log_success "✅ Vulnerable security group rules created!"
echo ""

# Verify the security group
log_info "📋 Security Group Details:"
aws ec2 describe-security-groups \
    --region "$REGION" \
    --group-ids "$SG_ID" \
    --query 'SecurityGroups[0].{GroupId:GroupId,GroupName:GroupName,VpcId:VpcId,IngressRules:length(IpPermissions)}' \
    --output table

echo ""
log_success "═══════════════════════════════════════════════════════════════════"
log_success "🎯 VULNERABLE SECURITY GROUP CREATED SUCCESSFULLY!"
log_success "═══════════════════════════════════════════════════════════════════"
echo ""
log_info "Security Group ID: $SG_ID"
log_info "Dangerous Rules Created: 4 (SSH, RDP, PostgreSQL, MySQL all open to 0.0.0.0/0)"
echo ""
log_warning "⏰ GuardDuty Finding Timeline:"
echo "  • Detection time: 5-15 minutes"
echo "  • Finding type: Recon:EC2/PortProbeUnprotectedPort or Policy:IAMUser/RootCredentialUsage"
echo "  • Severity: HIGH (~7.0-8.0)"
echo "  • EventBridge event: Automatically sent to your rule"
echo "  • Lambda trigger: Automatic when finding is created"
echo ""
log_info "What happens next:"
echo "  1. ⏱️  GuardDuty analyzes the security group (5-15 min)"
echo "  2. 🚨 GuardDuty creates HIGH severity finding automatically"
echo "  3. 📤 GuardDuty sends event to EventBridge automatically"
echo "  4. 🎯 EventBridge triggers your Lambda function automatically"
echo "  5. ⚡ Lambda processes the finding"
echo ""
log_info "Monitor your findings:"
echo ""
echo "  📊 GuardDuty Console (check in 10-15 minutes):"
echo "     https://$REGION.console.aws.amazon.com/guardduty/home?region=$REGION#/findings"
echo ""
echo "  📈 Lambda Function Logs:"
echo "     https://$REGION.console.aws.amazon.com/cloudwatch/home?region=$REGION#logsV2:log-groups/log-group/\$252Faws\$252Flambda\$252Fcustodian-guardduty-high-severity-findings"
echo ""
echo "  🔍 Check for findings (after 15 minutes):"
echo "     aws guardduty list-findings --detector-id $DETECTOR_ID --region $REGION --finding-criteria '{\"severity\":{\"gte\":7.0}}'"
echo ""
log_warning "🧹 CLEANUP: To delete the vulnerable security group, run:"
echo "     aws ec2 delete-security-group --group-id $SG_ID --region $REGION"
echo ""
log_info "Press Ctrl+C to cleanup and exit, or wait for findings to be generated..."
echo ""

# Keep the security group active for a while to ensure GuardDuty detects it
log_info "Keeping security group active for 20 minutes to ensure GuardDuty detection..."
log_info "Checking for findings every 2 minutes..."
echo ""

for i in {1..10}; do
    ELAPSED=$((i * 2))
    log_info "⏰ Check $i/10 (after $ELAPSED minutes)..."
    
    # Check for recent findings
    FINDINGS=$(aws guardduty list-findings \
        --detector-id "$DETECTOR_ID" \
        --region "$REGION" \
        --finding-criteria "{\"severity\":{\"gte\":7.0},\"updatedAt\":{\"gte\":$(($(date +%s) - 1800))000}}" \
        --max-items 20 \
        --query 'FindingIds' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$FINDINGS" && "$FINDINGS" != "None" ]]; then
        FINDING_COUNT=$(echo "$FINDINGS" | wc -w)
        echo ""
        log_success "🎉 FINDING DETECTED! Found $FINDING_COUNT HIGH/CRITICAL findings!"
        echo ""
        
        # Show finding details
        FIRST_FINDING=$(echo "$FINDINGS" | awk '{print $1}')
        log_info "📋 Finding Details:"
        aws guardduty get-findings \
            --detector-id "$DETECTOR_ID" \
            --region "$REGION" \
            --finding-ids "$FIRST_FINDING" \
            --query 'Findings[0].{Type:Type,Severity:Severity,Title:Title,Description:Description,UpdatedAt:UpdatedAt}' \
            --output table
        
        echo ""
        log_success "✅ GuardDuty finding created and should trigger Lambda soon!"
        
        # Check Lambda invocations
        log_info "Checking Lambda invocations..."
        sleep 30
        
        INVOCATIONS=$(aws cloudwatch get-metric-statistics \
            --namespace "AWS/Lambda" \
            --metric-name "Invocations" \
            --dimensions Name=FunctionName,Value=custodian-guardduty-high-severity-findings \
            --start-time "$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -v-10M +%Y-%m-%dT%H:%M:%S)" \
            --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
            --period 600 \
            --statistics Sum \
            --region "$REGION" \
            --query 'Datapoints[0].Sum' \
            --output text 2>/dev/null || echo "0")
        
        if [[ "$INVOCATIONS" != "None" && "$INVOCATIONS" != "0" && -n "$INVOCATIONS" ]]; then
            log_success "🚀 Lambda was invoked $INVOCATIONS time(s)! Integration is working!"
        else
            log_info "Lambda invocation not detected yet, may need more time..."
        fi
        
        break
    else
        log_info "No findings detected yet, waiting..."
    fi
    
    if [ $i -lt 10 ]; then
        sleep 120  # Wait 2 minutes
    fi
done

echo ""
log_success "Script complete. Security group $SG_ID will be cleaned up on exit."
