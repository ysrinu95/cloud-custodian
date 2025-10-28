#!/bin/bash

# Fix the EventBridge rule for GuardDuty to use the correct event pattern

set -e

REGION="${AWS_REGION:-us-east-1}"
RULE_NAME="custodian-guardduty-high-severity-findings"

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
log_info "🔧 Fixing EventBridge rule for GuardDuty findings..."
echo ""

# Show current event pattern
log_info "📋 Current event pattern:"
CURRENT_PATTERN=$(aws events describe-rule --name "$RULE_NAME" --region "$REGION" --query 'EventPattern' --output text)
echo "$CURRENT_PATTERN"
echo ""

# The correct event pattern for GuardDuty findings
CORRECT_PATTERN='{
  "source": ["aws.guardduty"],
  "detail-type": ["GuardDuty Finding"],
  "detail": {
    "severity": [
      {"numeric": [">=", 7.0]}
    ]
  }
}'

log_warning "📝 Updating EventBridge rule with correct event pattern..."
echo ""
log_info "New pattern will match:"
echo "  • Source: aws.guardduty"
echo "  • Detail Type: GuardDuty Finding"
echo "  • Severity: >= 7.0 (HIGH and CRITICAL)"
echo ""

# Update the rule
aws events put-rule \
    --name "$RULE_NAME" \
    --region "$REGION" \
    --event-pattern "$CORRECT_PATTERN" \
    --state ENABLED \
    --description "Cloud Custodian - GuardDuty HIGH/CRITICAL severity findings" \
    > /dev/null

if [ $? -eq 0 ]; then
    log_success "✅ EventBridge rule updated successfully!"
else
    log_error "❌ Failed to update EventBridge rule"
    exit 1
fi

echo ""
log_info "🔍 Verifying updated pattern:"
UPDATED_PATTERN=$(aws events describe-rule --name "$RULE_NAME" --region "$REGION" --query 'EventPattern' --output text)
echo "$UPDATED_PATTERN"

echo ""
log_success "🎯 EventBridge rule is now configured correctly!"
log_info "The rule will now trigger on REAL GuardDuty findings with severity >= 7.0"
echo ""

log_info "📊 Next steps:"
echo "  1. Run: ./c7n/scripts/trigger-guardduty-lambda.sh"
echo "     This will send test GuardDuty Finding events to EventBridge"
echo ""
echo "  2. Check Lambda invocations in CloudWatch:"
echo "     https://$REGION.console.aws.amazon.com/cloudwatch/home?region=$REGION#logsV2:log-groups/log-group/\$252Faws\$252Flambda\$252Fcustodian-guardduty-high-severity-findings"
echo ""
echo "  3. Monitor EventBridge metrics:"
echo "     https://$REGION.console.aws.amazon.com/cloudwatch/home?region=$REGION#metricsV2:graph=~();query=~'*7bAWS*2fEvents*2cRuleName*7d*20custodian-guardduty-high-severity-findings"
