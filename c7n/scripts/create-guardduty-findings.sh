#!/bin/bash

# Simple script to create REAL GuardDuty findings using create-sample-findings API
# These findings will appear in the GuardDuty console and can trigger Lambda functions

set -e

# Configuration
REGION="${AWS_REGION:-us-east-1}"

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

# Get GuardDuty detector ID
log_info "🔍 Finding GuardDuty detector..."
DETECTOR_ID=$(aws guardduty list-detectors \
    --region "$REGION" \
    --query 'DetectorIds[0]' \
    --output text 2>/dev/null || echo "None")

if [[ "$DETECTOR_ID" == "None" || -z "$DETECTOR_ID" ]]; then
    log_error "GuardDuty is not enabled in region $REGION"
    log_info "Enabling GuardDuty..."
    DETECTOR_ID=$(aws guardduty create-detector \
        --region "$REGION" \
        --enable \
        --query 'DetectorId' \
        --output text)
    log_success "GuardDuty enabled with detector ID: $DETECTOR_ID"
else
    log_success "GuardDuty detector found: $DETECTOR_ID"
fi

echo ""
log_info "🎯 Creating REAL HIGH and CRITICAL severity GuardDuty findings..."
echo ""

# Create HIGH severity findings
log_warning "📋 Creating HIGH severity findings..."
aws guardduty create-sample-findings \
    --detector-id "$DETECTOR_ID" \
    --region "$REGION" \
    --finding-types "Recon:EC2/PortProbeUnprotectedPort" \
                    "UnauthorizedAccess:EC2/SSHBruteForce" \
                    "Backdoor:EC2/C&CActivity.B!DNS" \
    2>/dev/null

if [ $? -eq 0 ]; then
    log_success "✅ HIGH severity findings created:"
    echo "   • Recon:EC2/PortProbeUnprotectedPort"
    echo "   • UnauthorizedAccess:EC2/SSHBruteForce"
    echo "   • Backdoor:EC2/C&CActivity.B!DNS"
else
    log_error "Failed to create HIGH findings"
    exit 1
fi

echo ""
sleep 3

# Create CRITICAL severity findings
log_warning "📋 Creating CRITICAL severity findings..."
aws guardduty create-sample-findings \
    --detector-id "$DETECTOR_ID" \
    --region "$REGION" \
    --finding-types "CryptoCurrency:EC2/BitcoinTool.B!DNS" \
                    "Trojan:EC2/DropPoint!DNS" \
                    "Trojan:EC2/BlackholeTraffic!DNS" \
    2>/dev/null

if [ $? -eq 0 ]; then
    log_success "✅ CRITICAL severity findings created:"
    echo "   • CryptoCurrency:EC2/BitcoinTool.B!DNS"
    echo "   • Trojan:EC2/DropPoint!DNS"
    echo "   • Trojan:EC2/BlackholeTraffic!DNS"
else
    log_error "Failed to create CRITICAL findings"
    exit 1
fi

echo ""
log_info "⏳ Waiting 30 seconds for GuardDuty to process findings..."
sleep 30

# Verify findings
log_info "🔍 Verifying findings in GuardDuty console..."
FINDINGS=$(aws guardduty list-findings \
    --detector-id "$DETECTOR_ID" \
    --region "$REGION" \
    --finding-criteria '{"severity":{"gte":7.0}}' \
    --max-items 20 \
    --query 'FindingIds' \
    --output text 2>/dev/null)

if [[ -n "$FINDINGS" && "$FINDINGS" != "None" ]]; then
    FINDING_COUNT=$(echo "$FINDINGS" | wc -w)
    echo ""
    log_success "🎉 SUCCESS: $FINDING_COUNT HIGH/CRITICAL findings visible in GuardDuty!"
    
    # Show first finding details
    FIRST_FINDING=$(echo "$FINDINGS" | awk '{print $1}')
    echo ""
    log_info "📊 Sample finding details:"
    aws guardduty get-findings \
        --detector-id "$DETECTOR_ID" \
        --region "$REGION" \
        --finding-ids "$FIRST_FINDING" \
        --query 'Findings[0].{Type:Type,Severity:Severity,Title:Title,UpdatedAt:UpdatedAt}' \
        --output table 2>/dev/null
    
    echo ""
    log_success "✅ Findings successfully created and visible in GuardDuty console!"
    echo ""
    log_info "🌐 View in console: https://$REGION.console.aws.amazon.com/guardduty/home?region=$REGION#/findings"
    log_info "📊 Filter by: Severity >= 7.0 (HIGH and CRITICAL)"
    log_info "🚀 These findings should trigger your Cloud Custodian Lambda functions"
    echo ""
else
    log_warning "⚠️  Findings created but may need more time to appear"
    log_info "💡 Check GuardDuty console in 1-2 minutes"
    log_info "🌐 Console: https://$REGION.console.aws.amazon.com/guardduty/home?region=$REGION#/findings"
fi

echo ""
log_info "📋 To list findings later, run:"
echo "  aws guardduty list-findings --detector-id $DETECTOR_ID --region $REGION"
