#!/bin/bash

# Script to trigger GuardDuty Lambda functions by sending GuardDuty Finding events to EventBridge
# This simulates real GuardDuty findings that will invoke your Cloud Custodian Lambda functions

set -e

REGION="${AWS_REGION:-us-east-1}"
EVENT_BUS="default"

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
log_info "🔍 Getting GuardDuty detector ID..."
DETECTOR_ID=$(aws guardduty list-detectors \
    --region "$REGION" \
    --query 'DetectorIds[0]' \
    --output text 2>/dev/null || echo "None")

if [[ "$DETECTOR_ID" == "None" || -z "$DETECTOR_ID" ]]; then
    log_error "GuardDuty is not enabled in region $REGION"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

log_success "Detector ID: $DETECTOR_ID"
log_success "Account ID: $ACCOUNT_ID"
echo ""

log_info "🎯 Sending HIGH severity GuardDuty Finding event to EventBridge..."

# Create a HIGH severity GuardDuty Finding event
HIGH_EVENT=$(cat <<EOF
[
  {
    "Source": "aws.guardduty",
    "DetailType": "GuardDuty Finding",
    "Detail": "{\"schemaVersion\":\"2.0\",\"accountId\":\"$ACCOUNT_ID\",\"region\":\"$REGION\",\"partition\":\"aws\",\"id\":\"demo-high-finding-$(date +%s)\",\"arn\":\"arn:aws:guardduty:$REGION:$ACCOUNT_ID:detector/$DETECTOR_ID/finding/demo-high-finding-$(date +%s)\",\"type\":\"UnauthorizedAccess:EC2/SSHBruteForce\",\"resource\":{\"resourceType\":\"Instance\",\"instanceDetails\":{\"instanceId\":\"i-demo12345678\"}},\"service\":{\"serviceName\":\"guardduty\",\"detectorId\":\"$DETECTOR_ID\",\"action\":{\"actionType\":\"NETWORK_CONNECTION\"},\"eventFirstSeen\":\"$TIMESTAMP\",\"eventLastSeen\":\"$TIMESTAMP\",\"archived\":false,\"count\":1},\"severity\":8.0,\"createdAt\":\"$TIMESTAMP\",\"updatedAt\":\"$TIMESTAMP\",\"title\":\"Demo HIGH Severity - SSH Brute Force Attack\",\"description\":\"Simulated HIGH severity GuardDuty finding for testing Cloud Custodian Lambda functions\"}",
    "Resources": [],
    "Time": "$TIMESTAMP"
  }
]
EOF
)

# Send HIGH severity event
aws events put-events --entries "$HIGH_EVENT" --region "$REGION" > /dev/null

if [ $? -eq 0 ]; then
    log_success "✅ HIGH severity GuardDuty Finding event sent!"
    echo "   • Type: UnauthorizedAccess:EC2/SSHBruteForce"
    echo "   • Severity: 8.0 (HIGH)"
else
    log_error "Failed to send HIGH severity event"
    exit 1
fi

echo ""
sleep 2

log_info "🎯 Sending CRITICAL severity GuardDuty Finding event to EventBridge..."

# Create a CRITICAL severity GuardDuty Finding event
CRITICAL_EVENT=$(cat <<EOF
[
  {
    "Source": "aws.guardduty",
    "DetailType": "GuardDuty Finding",
    "Detail": "{\"schemaVersion\":\"2.0\",\"accountId\":\"$ACCOUNT_ID\",\"region\":\"$REGION\",\"partition\":\"aws\",\"id\":\"demo-critical-finding-$(date +%s)\",\"arn\":\"arn:aws:guardduty:$REGION:$ACCOUNT_ID:detector/$DETECTOR_ID/finding/demo-critical-finding-$(date +%s)\",\"type\":\"CryptoCurrency:EC2/BitcoinTool.B!DNS\",\"resource\":{\"resourceType\":\"Instance\",\"instanceDetails\":{\"instanceId\":\"i-demo87654321\"}},\"service\":{\"serviceName\":\"guardduty\",\"detectorId\":\"$DETECTOR_ID\",\"action\":{\"actionType\":\"DNS_REQUEST\"},\"eventFirstSeen\":\"$TIMESTAMP\",\"eventLastSeen\":\"$TIMESTAMP\",\"archived\":false,\"count\":1},\"severity\":9.5,\"createdAt\":\"$TIMESTAMP\",\"updatedAt\":\"$TIMESTAMP\",\"title\":\"Demo CRITICAL Severity - Cryptocurrency Mining Detected\",\"description\":\"Simulated CRITICAL severity GuardDuty finding for testing Cloud Custodian Lambda functions\"}",
    "Resources": [],
    "Time": "$TIMESTAMP"
  }
]
EOF
)

# Send CRITICAL severity event
aws events put-events --entries "$CRITICAL_EVENT" --region "$REGION" > /dev/null

if [ $? -eq 0 ]; then
    log_success "✅ CRITICAL severity GuardDuty Finding event sent!"
    echo "   • Type: CryptoCurrency:EC2/BitcoinTool.B!DNS"
    echo "   • Severity: 9.5 (CRITICAL)"
else
    log_error "Failed to send CRITICAL severity event"
    exit 1
fi

echo ""
log_info "⏳ Waiting 10 seconds for Lambda functions to be invoked..."
sleep 10

echo ""
log_info "🔍 Checking for Lambda function invocations..."

# Find Cloud Custodian Lambda functions
CUSTODIAN_FUNCTIONS=$(aws lambda list-functions \
    --region "$REGION" \
    --query 'Functions[?starts_with(FunctionName, `custodian-`)].FunctionName' \
    --output text 2>/dev/null)

if [[ -z "$CUSTODIAN_FUNCTIONS" ]]; then
    log_warning "No Cloud Custodian Lambda functions found"
    exit 0
fi

echo ""
log_info "📊 Lambda Invocation Check:"
echo "=============================================="

INVOCATION_FOUND=false

for FUNC in $CUSTODIAN_FUNCTIONS; do
    if [[ "$FUNC" == *"guardduty"* || "$FUNC" == *"security"* ]]; then
        # Check CloudWatch metrics for recent invocations
        INVOCATIONS=$(aws cloudwatch get-metric-statistics \
            --namespace "AWS/Lambda" \
            --metric-name "Invocations" \
            --dimensions Name=FunctionName,Value="$FUNC" \
            --start-time "$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -v-5M +%Y-%m-%dT%H:%M:%S)" \
            --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
            --period 300 \
            --statistics Sum \
            --region "$REGION" \
            --query 'Datapoints[0].Sum' \
            --output text 2>/dev/null || echo "0")
        
        if [[ "$INVOCATIONS" != "None" && "$INVOCATIONS" != "0" && -n "$INVOCATIONS" ]]; then
            log_success "✅ $FUNC: $INVOCATIONS invocations"
            INVOCATION_FOUND=true
            
            # Get recent logs
            log_info "   📝 Recent logs:"
            aws logs filter-log-events \
                --log-group-name "/aws/lambda/$FUNC" \
                --region "$REGION" \
                --start-time $(( ($(date +%s) - 300) * 1000 )) \
                --max-items 3 \
                --query 'events[*].message' \
                --output text 2>/dev/null | head -5 || echo "   No recent logs"
        else
            echo "⚪ $FUNC: No recent invocations"
        fi
    fi
done

echo "=============================================="
echo ""

if [ "$INVOCATION_FOUND" = true ]; then
    log_success "🎉 SUCCESS! Lambda functions were invoked by GuardDuty Finding events!"
    log_info "📊 Your EventBridge → Lambda integration is working correctly"
else
    log_warning "⚠️  No Lambda invocations detected"
    echo ""
    log_info "💡 Troubleshooting steps:"
    log_info "1. Check EventBridge rule event pattern:"
    log_info "   aws events describe-rule --name custodian-guardduty-high-severity-findings --region $REGION"
    echo ""
    log_info "2. The event pattern should be:"
    log_info '   {"source": ["aws.guardduty"], "detail-type": ["GuardDuty Finding"]}'
    echo ""
    log_info "3. NOT this (incorrect):"
    log_info '   {"detail-type": ["AWS API Call via CloudTrail"], "detail": {"eventSource": ["aws.guardduty"]}}'
    echo ""
    log_info "4. Check Lambda function CloudWatch Logs:"
    log_info "   https://$REGION.console.aws.amazon.com/cloudwatch/home?region=$REGION#logsV2:log-groups"
fi

echo ""
log_info "🌐 EventBridge Console: https://$REGION.console.aws.amazon.com/events/home?region=$REGION#/rules"
log_info "📊 Lambda Console: https://$REGION.console.aws.amazon.com/lambda/home?region=$REGION#/functions"
