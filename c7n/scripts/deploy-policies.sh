#!/bin/bash
# Deploys c7n policies using custodian CLI

output_dir=s3://ysr95-cloud-custodian-logs-26zsuuw4
policy_dir=policies
dryrun=
region=${AWS_REGION:-us-east-1}

while getopts 'ldr:' OPTION; do
  case "$OPTION" in
    l)
      echo "local run..."
      output_dir=output
      ;;
    d)
      echo "running deploy as dry run..."
      dryrun=--dryrun
      ;;
    r)
      echo "running deploy for region [$OPTARG]..."
      region="$OPTARG"
      ;;
    ?)
      echo "script usage: $(basename $0) [-l] [-d] [-r <region>]" >&2
      exit 1
      ;;
  esac
done

echo "════════════════════════════════════════════════════════"
echo "Cloud Custodian Policy Deployment"
echo "════════════════════════════════════════════════════════"
echo "Output Directory: $output_dir"
echo "Policy Directory: $policy_dir"
echo "Region: $region"
echo "Dry Run: ${dryrun:-false}"
echo "════════════════════════════════════════════════════════"
echo ""

deployment_errors=0
deployment_success=0
total_policies=0

for FILE in $policy_dir/*.yml; do
  if [ -f "$FILE" ]; then
    echo "📄 Deploying policy file: $FILE"
    
    # Check if file has any policies (not empty or baseline)
    # Use tr to remove any whitespace/newlines and ensure we get a clean number
    policy_count=$(grep -c "^  - name:" "$FILE" 2>/dev/null | tr -d '[:space:]' || echo "0")
    
    # Ensure policy_count is a valid integer
    if ! [[ "$policy_count" =~ ^[0-9]+$ ]]; then
      policy_count=0
    fi
    
    if [ "$policy_count" -eq 0 ]; then
      echo "⚠️  Skipping $FILE (no policies found or baseline file)"
      echo ""
      continue
    fi
    
    echo "   Found $policy_count policy(ies) in file"
    total_policies=$((total_policies + policy_count))
    
    # Deploy using custodian CLI (not c7n-org)
    if custodian run \
      --region "$region" \
      --output-dir "$output_dir" \
      $dryrun \
      "$FILE"; then
      echo "✅ Successfully deployed: $FILE"
      deployment_success=$((deployment_success + 1))
    else
      echo "❌ Failed to deploy: $FILE"
      deployment_errors=$((deployment_errors + 1))
    fi
    echo ""
  fi
done

echo ""
echo "════════════════════════════════════════════════════════"
echo "Deployment Summary"
echo "════════════════════════════════════════════════════════"
echo "Total Policy Files: $((deployment_success + deployment_errors))"
echo "Total Policies: $total_policies"
echo "✅ Successful Deployments: $deployment_success"
echo "❌ Failed Deployments: $deployment_errors"
echo "════════════════════════════════════════════════════════"

if [ "$deployment_errors" -gt 0 ]; then
  echo "❌ Deployment completed with errors"
  exit 1
else
  echo "✅ All deployments completed successfully"
  exit 0
fi