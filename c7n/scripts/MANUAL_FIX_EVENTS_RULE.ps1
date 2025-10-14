# Manual fix for CloudWatch Events rule deletion issue
# This PowerShell script provides manual commands to fix the "Rule can't be deleted since it has targets" error

Write-Host "=" * 80 -ForegroundColor Blue
Write-Host "MANUAL FIX FOR CLOUDWATCH EVENTS RULE DELETION ERROR" -ForegroundColor Yellow
Write-Host "=" * 80 -ForegroundColor Blue
Write-Host ""

Write-Host "PROBLEM:" -ForegroundColor Red
Write-Host "You're getting this error when trying to delete a CloudWatch Events rule:" -ForegroundColor White
Write-Host 'An error occurred (ValidationException) when calling the DeleteRule operation: Rule can\'t be deleted since it has targets.' -ForegroundColor Gray
Write-Host ""

Write-Host "CAUSE:" -ForegroundColor Red
Write-Host "CloudWatch Events rules must have all targets removed before the rule can be deleted." -ForegroundColor White
Write-Host ""

Write-Host "SOLUTION OPTIONS:" -ForegroundColor Green
Write-Host ""

Write-Host "OPTION 1: Using AWS CLI (if you have it installed)" -ForegroundColor Cyan
Write-Host "-" * 50 -ForegroundColor Gray
Write-Host "# First, list the targets for the rule:" -ForegroundColor Green
Write-Host 'aws events list-targets-by-rule --rule "custodian-ebs-unencrypted-volumes-scheduled"' -ForegroundColor Gray
Write-Host ""
Write-Host "# Remove all targets (replace target-ids with actual IDs from above command):" -ForegroundColor Green
Write-Host 'aws events remove-targets --rule "custodian-ebs-unencrypted-volumes-scheduled" --ids target-id-1 target-id-2' -ForegroundColor Gray
Write-Host ""
Write-Host "# Finally, delete the rule:" -ForegroundColor Green
Write-Host 'aws events delete-rule --name "custodian-ebs-unencrypted-volumes-scheduled"' -ForegroundColor Gray
Write-Host ""

Write-Host "OPTION 2: Using AWS Console" -ForegroundColor Cyan
Write-Host "-" * 50 -ForegroundColor Gray
Write-Host "1. Go to AWS Console > CloudWatch > Events > Rules" -ForegroundColor White
Write-Host "2. Find the rule: custodian-ebs-unencrypted-volumes-scheduled" -ForegroundColor White
Write-Host "3. Click on the rule to view its details" -ForegroundColor White
Write-Host "4. Go to 'Targets' tab and remove all targets" -ForegroundColor White
Write-Host "5. Then delete the rule from the 'Actions' menu" -ForegroundColor White
Write-Host ""

Write-Host "OPTION 3: Using AWS PowerShell Module" -ForegroundColor Cyan
Write-Host "-" * 50 -ForegroundColor Gray
Write-Host "# Install AWS PowerShell module if not already installed:" -ForegroundColor Green
Write-Host 'Install-Module -Name AWS.Tools.CloudWatchEvents -Force' -ForegroundColor Gray
Write-Host ""
Write-Host "# List targets:" -ForegroundColor Green
Write-Host 'Get-CWETargetsByRule -Rule "custodian-ebs-unencrypted-volumes-scheduled"' -ForegroundColor Gray
Write-Host ""
Write-Host "# Remove targets (replace with actual target IDs):" -ForegroundColor Green
Write-Host 'Remove-CWETarget -Rule "custodian-ebs-unencrypted-volumes-scheduled" -Id @("target-id-1", "target-id-2")' -ForegroundColor Gray
Write-Host ""
Write-Host "# Delete the rule:" -ForegroundColor Green
Write-Host 'Remove-CWERule -Name "custodian-ebs-unencrypted-volumes-scheduled"' -ForegroundColor Gray
Write-Host ""

Write-Host "OPTION 4: Update Your Cleanup Script" -ForegroundColor Cyan
Write-Host "-" * 50 -ForegroundColor Gray
Write-Host "The enhanced cleanup scripts I created will handle this automatically:" -ForegroundColor White
Write-Host "- c7n/scripts/mugc-enhanced.py (enhanced garbage collection)" -ForegroundColor Gray
Write-Host "- c7n/scripts/cleanup_events_rule.py (specific rule cleanup)" -ForegroundColor Gray
Write-Host "- c7n/scripts/clean-removed-policies.sh (updated cleanup script)" -ForegroundColor Gray
Write-Host ""

Write-Host "PREVENTION:" -ForegroundColor Green
Write-Host "To prevent this issue in the future, use the enhanced cleanup script:" -ForegroundColor White
Write-Host 'c7n/scripts/clean-removed-policies.sh -d  # dry run first' -ForegroundColor Gray
Write-Host 'c7n/scripts/clean-removed-policies.sh     # actual cleanup' -ForegroundColor Gray
Write-Host ""

Write-Host "IMMEDIATE STEPS FOR YOUR CASE:" -ForegroundColor Yellow
Write-Host "1. Use AWS Console (easiest) or AWS CLI to manually remove targets from the rule" -ForegroundColor White
Write-Host "2. Then delete the rule" -ForegroundColor White
Write-Host "3. Re-run your cleanup process" -ForegroundColor White
Write-Host "4. Consider using the enhanced scripts for future cleanups" -ForegroundColor White
Write-Host ""

Write-Host "=" * 80 -ForegroundColor Blue