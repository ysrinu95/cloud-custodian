# IMMEDIATE SOLUTION FOR YOUR CLOUDWATCH EVENTS RULE ISSUE
# Rule: custodian-ebs-unencrypted-volumes-scheduled

Write-Host ""
Write-Host "🚨 IMMEDIATE FIX REQUIRED" -ForegroundColor Red
Write-Host "=" * 50 -ForegroundColor Yellow
Write-Host ""
Write-Host "You have a CloudWatch Events rule that can't be deleted because it has targets." -ForegroundColor White
Write-Host "Rule name: custodian-ebs-unencrypted-volumes-scheduled" -ForegroundColor Yellow
Write-Host ""

Write-Host "✅ QUICKEST SOLUTION: Use AWS Console" -ForegroundColor Green
Write-Host "-" * 40 -ForegroundColor Gray
Write-Host ""
Write-Host "1. Open your web browser and go to:" -ForegroundColor White
Write-Host "   https://console.aws.amazon.com/events/home" -ForegroundColor Cyan
Write-Host ""
Write-Host "2. Make sure you're in the correct region (probably us-east-1)" -ForegroundColor White
Write-Host ""
Write-Host "3. Click on 'Rules' in the left navigation" -ForegroundColor White
Write-Host ""
Write-Host "4. Find the rule: custodian-ebs-unencrypted-volumes-scheduled" -ForegroundColor White
Write-Host ""
Write-Host "5. Click on the rule name to open its details" -ForegroundColor White
Write-Host ""
Write-Host "6. Click on the 'Targets' tab" -ForegroundColor White
Write-Host ""
Write-Host "7. Select ALL targets (there should be checkboxes)" -ForegroundColor White
Write-Host ""
Write-Host "8. Click 'Remove' to remove all targets" -ForegroundColor White
Write-Host ""
Write-Host "9. Wait for the removal to complete" -ForegroundColor White
Write-Host ""
Write-Host "10. Go back to the Rules list" -ForegroundColor White
Write-Host ""
Write-Host "11. Select the rule and click 'Delete' or use Actions > Delete" -ForegroundColor White
Write-Host ""

Write-Host "⏱️ ESTIMATED TIME: 2-3 minutes" -ForegroundColor Blue
Write-Host ""

Write-Host "🔄 AFTER FIXING:" -ForegroundColor Green
Write-Host "-" * 20 -ForegroundColor Gray
Write-Host "1. Go back to your Cloud Custodian cleanup process" -ForegroundColor White
Write-Host "2. Re-run the cleanup command that failed" -ForegroundColor White
Write-Host "3. It should now complete successfully" -ForegroundColor White
Write-Host ""

Write-Host "💡 ALTERNATIVE: Install AWS CLI" -ForegroundColor Yellow
Write-Host "-" * 30 -ForegroundColor Gray
Write-Host "If you prefer command line:" -ForegroundColor White
Write-Host ""
Write-Host "1. Download and install AWS CLI from:" -ForegroundColor White
Write-Host "   https://aws.amazon.com/cli/" -ForegroundColor Cyan
Write-Host ""
Write-Host "2. Configure your credentials:" -ForegroundColor White
Write-Host "   aws configure" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Then run these commands:" -ForegroundColor White
Write-Host ""
Write-Host "   # List targets" -ForegroundColor Green
Write-Host '   aws events list-targets-by-rule --rule "custodian-ebs-unencrypted-volumes-scheduled"' -ForegroundColor Gray
Write-Host ""
Write-Host "   # Remove targets (replace target-ids with actual IDs from above)" -ForegroundColor Green
Write-Host '   aws events remove-targets --rule "custodian-ebs-unencrypted-volumes-scheduled" --ids target-id-1 target-id-2' -ForegroundColor Gray
Write-Host ""
Write-Host "   # Delete the rule" -ForegroundColor Green
Write-Host '   aws events delete-rule --name "custodian-ebs-unencrypted-volumes-scheduled"' -ForegroundColor Gray
Write-Host ""

Write-Host "🛡️ PREVENTION FOR FUTURE:" -ForegroundColor Blue
Write-Host "-" * 25 -ForegroundColor Gray
Write-Host "Use the enhanced cleanup scripts I created:" -ForegroundColor White
Write-Host "• c7n/scripts/clean-removed-policies.sh (updated with enhanced cleanup)" -ForegroundColor Gray
Write-Host "• c7n/scripts/mugc-enhanced.py (handles CloudWatch Events properly)" -ForegroundColor Gray
Write-Host ""

Write-Host "❓ NEED HELP?" -ForegroundColor Magenta
Write-Host "-" * 15 -ForegroundColor Gray
Write-Host "If you encounter any issues:" -ForegroundColor White
Write-Host "1. Check that you're in the right AWS region" -ForegroundColor White
Write-Host "2. Verify you have permissions to modify CloudWatch Events" -ForegroundColor White
Write-Host "3. Make sure you're looking at the correct AWS account" -ForegroundColor White
Write-Host ""

$response = Read-Host "Press Enter when you have completed the AWS Console steps above"
Write-Host ""
Write-Host "✅ Great! You should now be able to re-run your Cloud Custodian cleanup." -ForegroundColor Green
Write-Host "The rule custodian-ebs-unencrypted-volumes-scheduled should be fully removed." -ForegroundColor White