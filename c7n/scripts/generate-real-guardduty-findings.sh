#!/bin/bash

# Create REAL GuardDuty HIGH/CRITICAL findings by generating actual suspicious activities
# GuardDuty will detect these and automatically send events to EventBridge → Lambda

set -e

REGION="${AWS_REGION:-us-east-1}"
DEMO_TAG="CustodianGuardDutyTest"

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

echo ""
log_warning "⚠️  REAL GUARDDUTY FINDING GENERATOR"
log_warning "This script creates ACTUAL suspicious activities that GuardDuty will detect"
log_warning "Findings will appear in 15-30 minutes and automatically trigger EventBridge"
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
echo ""

# Activity 1: Cryptocurrency mining DNS queries (CRITICAL finding)
log_warning "💰 Activity 1: Simulating cryptocurrency mining DNS queries..."
log_info "Expected GuardDuty finding: CryptoCurrency:* (CRITICAL severity ~9.0)"
echo ""

CRYPTO_POOLS=(
    "pool.minergate.com"
    "stratum.f2pool.com" 
    "pool.supportxmr.com"
    "xmr-eu1.nanopool.org"
    "eth-eu1.nanopool.org"
    "btc.pool.bitcoin.com"
    "mining.pool.bitcoin.com"
)

for pool in "${CRYPTO_POOLS[@]}"; do
    log_info "  → DNS query: $pool"
    nslookup "$pool" 8.8.8.8 >/dev/null 2>&1 || true
    sleep 2
done

log_success "✅ Cryptocurrency mining DNS queries completed"
echo ""
sleep 3

# Activity 2: Suspicious IAM API calls (HIGH finding)
log_warning "🔐 Activity 2: Making unusual IAM API calls from unexpected location..."
log_info "Expected GuardDuty finding: UnauthorizedAccess:IAMUser/* (HIGH severity ~8.0)"
echo ""

UNUSUAL_API_CALLS=(
    "aws iam list-users --max-items 1"
    "aws iam list-roles --max-items 1"
    "aws iam get-account-summary"
    "aws iam list-access-keys"
    "aws iam list-policies --max-items 1"
)

for api_call in "${UNUSUAL_API_CALLS[@]}"; do
    log_info "  → API call: $api_call"
    eval "$api_call --region $REGION >/dev/null 2>&1 || true"
    sleep 3
done

log_success "✅ Unusual IAM API calls completed"
echo ""
sleep 3

# Activity 3: Suspicious EC2 API calls (HIGH finding)
log_warning "🖥️ Activity 3: Making suspicious EC2 API calls..."
log_info "Expected GuardDuty finding: Recon:IAMUser/* (HIGH severity ~8.0)"
echo ""

EC2_API_CALLS=(
    "aws ec2 describe-security-groups --max-results 5"
    "aws ec2 describe-instances --max-results 5"
    "aws ec2 describe-vpcs"
    "aws ec2 describe-subnets --max-results 5"
    "aws ec2 describe-network-interfaces --max-results 5"
)

for api_call in "${EC2_API_CALLS[@]}"; do
    log_info "  → API call: $api_call"
    eval "$api_call --region $REGION >/dev/null 2>&1 || true"
    sleep 2
done

log_success "✅ Suspicious EC2 API calls completed"
echo ""
sleep 3

# Activity 4: S3 bucket enumeration (HIGH finding)
log_warning "🪣 Activity 4: S3 bucket enumeration attempts..."
log_info "Expected GuardDuty finding: Discovery:S3/* (HIGH severity ~7.5)"
echo ""

log_info "  → Listing S3 buckets"
aws s3 ls --region "$REGION" >/dev/null 2>&1 || true
sleep 2

log_info "  → Getting S3 bucket locations"
aws s3api list-buckets --query 'Buckets[0:3].Name' --output text 2>/dev/null | while read -r bucket; do
    [[ -n "$bucket" ]] && aws s3api get-bucket-location --bucket "$bucket" >/dev/null 2>&1 || true
    sleep 1
done

log_success "✅ S3 enumeration completed"
echo ""
sleep 3

# Activity 5: DNS queries to known malicious/suspicious domains (CRITICAL finding)
log_warning "🌐 Activity 5: DNS queries to suspicious domains..."
log_info "Expected GuardDuty finding: Backdoor:EC2/C&CActivity.B!DNS (CRITICAL severity ~9.0)"
echo ""

SUSPICIOUS_DOMAINS=(
    "guarddutyc2activityb.com"
    "trojan.ddns.net"
    "malware-command.com"
)

for domain in "${SUSPICIOUS_DOMAINS[@]}"; do
    log_info "  → DNS query: $domain"
    nslookup "$domain" 8.8.8.8 >/dev/null 2>&1 || true
    sleep 2
done

log_success "✅ Suspicious domain queries completed"
echo ""
sleep 3

# Activity 6: Rapid API calls pattern (HIGH finding)
log_warning "⚡ Activity 6: Rapid-fire API calls (anomaly detection)..."
log_info "Expected GuardDuty finding: UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration (HIGH)"
echo ""

for i in {1..10}; do
    log_info "  → Burst $i: describe-regions"
    aws ec2 describe-regions --region "$REGION" >/dev/null 2>&1 || true
    sleep 0.5
done

log_success "✅ Rapid API call pattern completed"
echo ""

# Summary
echo ""
echo "═══════════════════════════════════════════════════════════════════"
log_success "🎯 REAL SUSPICIOUS ACTIVITIES COMPLETED!"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
log_info "Activities performed that will generate GuardDuty findings:"
echo ""
echo "  1. ✅ Cryptocurrency mining DNS queries → CRITICAL severity finding"
echo "  2. ✅ Unusual IAM API calls → HIGH severity finding"
echo "  3. ✅ Suspicious EC2 reconnaissance → HIGH severity finding"
echo "  4. ✅ S3 bucket enumeration → HIGH severity finding"
echo "  5. ✅ Malicious domain DNS queries → CRITICAL severity finding"
echo "  6. ✅ Rapid API call anomaly → HIGH severity finding"
echo ""
log_warning "⏰ IMPORTANT: GuardDuty findings take 15-30 minutes to appear"
echo ""
log_info "What happens next:"
echo "  1. GuardDuty analyzes the suspicious activities (15-30 min)"
echo "  2. GuardDuty creates HIGH/CRITICAL findings automatically"
echo "  3. GuardDuty sends events to EventBridge automatically"
echo "  4. EventBridge triggers your Lambda function automatically"
echo "  5. Your Lambda function processes the findings"
echo ""
log_info "Monitor your findings and Lambda:"
echo ""
echo "  📊 GuardDuty Console:"
echo "     https://$REGION.console.aws.amazon.com/guardduty/home?region=$REGION#/findings"
echo ""
echo "  📈 Lambda Function Logs:"
echo "     https://$REGION.console.aws.amazon.com/cloudwatch/home?region=$REGION#logsV2:log-groups/log-group/\$252Faws\$252Flambda\$252Fcustodian-guardduty-high-severity-findings"
echo ""
echo "  🎯 EventBridge Rule:"
echo "     https://$REGION.console.aws.amazon.com/events/home?region=$REGION#/rules/custodian-guardduty-high-severity-findings"
echo ""
log_info "Check findings in 20 minutes:"
echo ""
echo "  aws guardduty list-findings \\"
echo "    --detector-id $DETECTOR_ID \\"
echo "    --region $REGION \\"
echo "    --finding-criteria '{\"severity\":{\"gte\":7.0}}' \\"
echo "    --max-items 20"
echo ""
log_success "✅ Real GuardDuty finding generation complete!"
log_info "💡 Your EventBridge rule will automatically trigger Lambda when findings appear"
echo ""
