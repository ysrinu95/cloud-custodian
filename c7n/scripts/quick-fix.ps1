Write-Host ""
Write-Host "IMMEDIATE FIX FOR CLOUDWATCH EVENTS RULE ERROR" -ForegroundColor Red
Write-Host "=" * 50 -ForegroundColor Yellow
Write-Host ""
Write-Host "PROBLEM: Rule 'custodian-ebs-unencrypted-volumes-scheduled' has targets" -ForegroundColor White
Write-Host ""

Write-Host "QUICKEST SOLUTION: AWS Console (2-3 minutes)" -ForegroundColor Green
Write-Host "-" * 45 -ForegroundColor Gray
Write-Host ""
Write-Host "1. Go to: https://console.aws.amazon.com/events/home" -ForegroundColor Cyan
Write-Host ""
Write-Host "2. Click 'Rules' in left navigation" -ForegroundColor White
Write-Host ""
Write-Host "3. Find rule: custodian-ebs-unencrypted-volumes-scheduled" -ForegroundColor White
Write-Host ""
Write-Host "4. Click on the rule name" -ForegroundColor White
Write-Host ""
Write-Host "5. Go to 'Targets' tab" -ForegroundColor White
Write-Host ""
Write-Host "6. Select ALL targets and click 'Remove'" -ForegroundColor White
Write-Host ""
Write-Host "7. Go back and delete the rule" -ForegroundColor White
Write-Host ""

Write-Host "AFTER FIXING:" -ForegroundColor Green
Write-Host "- Re-run your Cloud Custodian cleanup" -ForegroundColor White
Write-Host "- It should complete without errors" -ForegroundColor White
Write-Host ""

Write-Host "PREVENTION:" -ForegroundColor Blue
Write-Host "- Use enhanced cleanup scripts in c7n/scripts/" -ForegroundColor White
Write-Host "- These handle CloudWatch Events properly" -ForegroundColor White
Write-Host ""

Read-Host "Press Enter to continue"