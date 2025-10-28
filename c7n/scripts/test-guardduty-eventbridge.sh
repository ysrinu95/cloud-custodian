#!/bin/bash

# Test script to verify GuardDuty → EventBridge → Lambda integration
# Sends a test GuardDuty Finding event to EventBridge to trigger Lambda

set -e

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

# Get account details
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
DETECTOR_ID=$(aws guardduty list-detectors --region "$REGION" --query 'DetectorIds[0]' --output text 2>/dev/null || echo "test-detector")

echo ""
log_info "🧪 Testing GuardDuty → EventBridge → Lambda Integration"
log_info "Account: $ACCOUNT_ID"
log_info "Region: $REGION"
echo ""

log_warning "📤 Sending HIGH severity GuardDuty Finding event to EventBridge..."

# Create HIGH severity test event (severity 8.0)
HIGH_EVENT=$(cat <<EOF
{
  "version": "0",
  "id": "$(uuidgen 2>/dev/null || echo 'test-event-high-'$(date +%s))",
  "detail-type": "GuardDuty Finding",
  "source": "aws.guardduty",
  "account": "$ACCOUNT_ID",
  "time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "region": "$REGION",
  "resources": [],
  "detail": {
    "schemaVersion": "2.0",
    "accountId": "$ACCOUNT_ID",
    "region": "$REGION",
    "partition": "aws",
    "id": "test-finding-high-$(date +%s)",
    "arn": "arn:aws:guardduty:$REGION:$ACCOUNT_ID:detector/$DETECTOR_ID/finding/test-finding-high-$(date +%s)",
    "type": "UnauthorizedAccess:EC2/SSHBruteForce",
    "resource": {
      "resourceType": "Instance",
      "instanceDetails": {
        "instanceId": "i-test12345678",
        "instanceType": "t3.micro"
      }
    },
    "service": {
      "serviceName": "guardduty",
      "detectorId": "$DETECTOR_ID",
      "action": {
        "actionType": "NETWORK_CONNECTION"
      },
      "eventFirstSeen": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
      "eventLastSeen": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
      "archived": false,
      "count": 1
    },
    "severity": 8.0,
    "createdAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "updatedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "title": "TEST: HIGH Severity - SSH Brute Force",
    "description": "Test event to verify GuardDuty EventBridge integration"
  }
}
EOF
)

# Send the event
echo "$HIGH_EVENT" > /tmp/guardduty-test-event.json

aws events put-events \
    --entries "$(cat /tmp/guardduty-test-event.json)" \
    --region "$REGION" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    log_success "✅ HIGH severity test event sent to EventBridge!"
    echo "   • Type: UnauthorizedAccess:EC2/SSHBruteForce"
    echo "   • Severity: 8.0"
else
    log_error "❌ Failed to send event"
    exit 1
fi

echo ""
sleep 2

log_warning "📤 Sending CRITICAL severity GuardDuty Finding event to EventBridge..."

# Create CRITICAL severity test event (severity 9.5)
CRITICAL_EVENT=$(cat <<EOF
{
  "version": "0",
  "id": "$(uuidgen 2>/dev/null || echo 'test-event-critical-'$(date +%s))",
  "detail-type": "GuardDuty Finding",
  "source": "aws.guardduty",
  "account": "$ACCOUNT_ID",
  "time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "region": "$REGION",
  "resources": [],
  "detail": {
    "schemaVersion": "2.0",
    "accountId": "$ACCOUNT_ID",
    "region": "$REGION",
    "partition": "aws",
    "id": "test-finding-critical-$(date +%s)",
    "arn": "arn:aws:guardduty:$REGION:$ACCOUNT_ID:detector/$DETECTOR_ID/finding/test-finding-critical-$(date +%s)",
    "type": "CryptoCurrency:EC2/BitcoinTool.B!DNS",
    "resource": {
      "resourceType": "Instance",
      "instanceDetails": {
        "instanceId": "i-test87654321",
        "instanceType": "t3.micro"
      }
    },
    "service": {
      "serviceName": "guardduty",
      "detectorId": "$DETECTOR_ID",
      "action": {
        "actionType": "DNS_REQUEST"
      },
      "eventFirstSeen": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
      "eventLastSeen": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
      "archived": false,
      "count": 1
    },
    "severity": 9.5,
    "createdAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "updatedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "title": "TEST: CRITICAL Severity - Cryptocurrency Mining",
    "description": "Test event to verify GuardDuty EventBridge integration"
  }
}
EOF
)

echo "$CRITICAL_EVENT" > /tmp/guardduty-test-event-critical.json

aws events put-events \
    --entries "$(cat /tmp/guardduty-test-event-critical.json)" \
    --region "$REGION" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    log_success "✅ CRITICAL severity test event sent to EventBridge!"
    echo "   • Type: CryptoCurrency:EC2/BitcoinTool.B!DNS"
    echo "   • Severity: 9.5"
else
    log_error "❌ Failed to send event"
    exit 1
fi

# Clean up temp files
rm -f /tmp/guardduty-test-event*.json

echo ""
log_info "⏳ Waiting 15 seconds for Lambda to process events..."
sleep 15

echo ""
log_info "🔍 Checking Lambda function invocations..."

# Check for Lambda invocations
LAMBDA_FUNCTION="custodian-guardduty-high-severity-findings"

INVOCATIONS=$(aws cloudwatch get-metric-statistics \
    --namespace "AWS/Lambda" \
    --metric-name "Invocations" \
    --dimensions Name=FunctionName,Value="$LAMBDA_FUNCTION" \
    --start-time "$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -v-5M +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 300 \
    --statistics Sum \
    --region "$REGION" \
    --query 'Datapoints[0].Sum' \
    --output text 2>/dev/null || echo "0")

echo ""
if [[ "$INVOCATIONS" != "None" && "$INVOCATIONS" != "0" && -n "$INVOCATIONS" ]]; then
    log_success "🎉 SUCCESS! Lambda function was invoked $INVOCATIONS time(s)!"
    log_success "✅ GuardDuty → EventBridge → Lambda integration is WORKING!"
    
    echo ""
    log_info "📝 Recent Lambda logs:"
    aws logs tail "/aws/lambda/$LAMBDA_FUNCTION" \
        --since 5m \
        --region "$REGION" \
        --format short 2>/dev/null | head -20 || echo "Could not retrieve logs"
else
    log_warning "⚠️  No Lambda invocations detected yet"
    log_info "💡 Check CloudWatch Logs manually:"
    echo "   https://$REGION.console.aws.amazon.com/cloudwatch/home?region=$REGION#logsV2:log-groups/log-group/\$252Faws\$252Flambda\$252F$LAMBDA_FUNCTION"
fi

echo ""
log_info "📊 EventBridge Console:"
echo "   https://$REGION.console.aws.amazon.com/events/home?region=$REGION#/rules/custodian-guardduty-high-severity-findings"
