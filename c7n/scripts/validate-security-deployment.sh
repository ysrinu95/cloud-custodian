#!/bin/bash
# Validation script to check if all security findings Lambda functions are deployed

REGION="${AWS_REGION:-us-east-1}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "🔍 Cloud Custodian Security Findings Lambda Validation"
echo "════════════════════════════════════════════════════════"
echo "Region: $REGION"
echo ""

# Expected Lambda functions based on security-findings.yml
EXPECTED_FUNCTIONS=(
    "custodian-guardduty-high-severity-findings"
    "custodian-config-compliance-violations"
    "custodian-securityhub-critical-findings"
    "custodian-macie-sensitive-data-findings"
    "custodian-iam-access-analyzer-external-access"
    "custodian-s3-access-logs-suspicious-activity"
    "custodian-cloudtrail-security-events"
    "custodian-security-findings-daily-summary"
    "custodian-config-compliance-tagger"
    "custodian-security-findings-aggregator"
)

# Check each function
FOUND=0
MISSING=0

for func in "${EXPECTED_FUNCTIONS[@]}"; do
    if aws lambda get-function --function-name "$func" --region "$REGION" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ $func${NC}"
        FOUND=$((FOUND + 1))
    else
        echo -e "${RED}❌ $func${NC}"
        MISSING=$((MISSING + 1))
    fi
done

echo ""
echo "Summary:"
echo -e "  ${GREEN}Found: $FOUND${NC}"
echo -e "  ${RED}Missing: $MISSING${NC}"

if [ $MISSING -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ All security findings Lambda functions are deployed!${NC}"
    echo "You can now run the security findings tests."
else
    echo ""
    echo -e "${YELLOW}⚠️  Some Lambda functions are missing.${NC}"
    echo "Deploy the security-findings.yml policies first:"
    echo ""
    echo "  custodian run -s output/ security-findings.yml --region $REGION"
fi

echo ""
echo "Additional checks:"

# Check SQS queue
if aws sqs get-queue-url --queue-name custodian-mailer-queue --region "$REGION" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ SQS custodian-mailer-queue exists${NC}"
else
    echo -e "${RED}❌ SQS custodian-mailer-queue missing${NC}"
fi

# Check IAM role
if aws iam get-role --role-name cloud-custodian >/dev/null 2>&1; then
    echo -e "${GREEN}✅ IAM role cloud-custodian exists${NC}"
else
    echo -e "${RED}❌ IAM role cloud-custodian missing${NC}"
fi

# Check CloudWatch Events rules
RULES_COUNT=$(aws events list-rules --name-prefix custodian --region "$REGION" --query 'length(Rules)' --output text 2>/dev/null || echo "0")
if [ "$RULES_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✅ CloudWatch Events rules: $RULES_COUNT found${NC}"
else
    echo -e "${YELLOW}⚠️  No CloudWatch Events rules found${NC}"
fi

echo ""
echo "To start testing, run:"
echo "  ./c7n/scripts/test-security-findings.sh"
echo "  or use the Jenkins pipeline: cloud-custodian-demo.groovy"