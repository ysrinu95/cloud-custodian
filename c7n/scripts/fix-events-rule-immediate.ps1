# Direct PowerShell solution for CloudWatch Events rule cleanup
# This script uses native .NET HTTP client to make AWS API calls

param(
    [Parameter(Mandatory=$true)]
    [string]$RuleName = "custodian-ebs-unencrypted-volumes-scheduled",
    
    [Parameter(Mandatory=$false)]
    [string]$Region = "us-east-1",
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun = $false
)

# Check if we can find AWS credentials in environment or files
function Get-AWSCredentials {
    # Try environment variables first
    $accessKey = $env:AWS_ACCESS_KEY_ID
    $secretKey = $env:AWS_SECRET_ACCESS_KEY
    $sessionToken = $env:AWS_SESSION_TOKEN
    
    if ($accessKey -and $secretKey) {
        return @{
            AccessKey = $accessKey
            SecretKey = $secretKey
            SessionToken = $sessionToken
        }
    }
    
    # Try AWS credentials file
    $credFile = "$env:USERPROFILE\.aws\credentials"
    if (Test-Path $credFile) {
        Write-Host "[INFO] Found AWS credentials file at $credFile" -ForegroundColor Blue
        Write-Host "[INFO] Please ensure your AWS credentials are configured" -ForegroundColor Blue
        return $null
    }
    
    Write-Host "[ERROR] No AWS credentials found. Please configure AWS credentials first." -ForegroundColor Red
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "1. Set environment variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY" -ForegroundColor Yellow
    Write-Host "2. Configure AWS CLI: aws configure" -ForegroundColor Yellow
    Write-Host "3. Use AWS SSO or other credential providers" -ForegroundColor Yellow
    return $null
}

Write-Host "=" * 70 -ForegroundColor Blue
Write-Host "CLOUDWATCH EVENTS RULE CLEANUP SOLUTION" -ForegroundColor Yellow
Write-Host "=" * 70 -ForegroundColor Blue
Write-Host ""
Write-Host "Problem: Rule '$RuleName' can't be deleted because it has targets" -ForegroundColor Red
Write-Host "Solution: Remove targets first, then delete the rule" -ForegroundColor Green
Write-Host ""

# Check for AWS CLI as the most reliable option
$awsCliAvailable = $false
try {
    $awsVersion = aws --version 2>$null
    if ($LASTEXITCODE -eq 0) {
        $awsCliAvailable = $true
        Write-Host "[SUCCESS] AWS CLI is available: $awsVersion" -ForegroundColor Green
    }
} catch {
    Write-Host "[INFO] AWS CLI not found in PATH" -ForegroundColor Yellow
}

if ($awsCliAvailable) {
    Write-Host ""
    Write-Host "USING AWS CLI APPROACH:" -ForegroundColor Cyan
    Write-Host "-" * 40 -ForegroundColor Gray
    
    # Step 1: List targets
    Write-Host "Step 1: Listing targets for rule '$RuleName'..." -ForegroundColor Blue
    $listCmd = "aws events list-targets-by-rule --rule `"$RuleName`" --region $Region"
    Write-Host "Command: $listCmd" -ForegroundColor Gray
    
    try {
        $targetsJson = Invoke-Expression $listCmd
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] Failed to list targets. Check if the rule exists and you have permissions." -ForegroundColor Red
            exit 1
        }
        
        $targets = $targetsJson | ConvertFrom-Json
        $targetList = $targets.Targets
        
        if (-not $targetList -or $targetList.Count -eq 0) {
            Write-Host "[INFO] No targets found for rule '$RuleName'. Proceeding to delete rule..." -ForegroundColor Blue
        } else {
            $targetIds = $targetList | ForEach-Object { $_.Id }
            $targetIdString = $targetIds -join " "
            Write-Host "[INFO] Found $($targetList.Count) target(s): $targetIdString" -ForegroundColor Blue
            
            # Step 2: Remove targets
            Write-Host ""
            Write-Host "Step 2: Removing targets from rule '$RuleName'..." -ForegroundColor Blue
            $removeCmd = "aws events remove-targets --rule `"$RuleName`" --ids $targetIdString --region $Region"
            Write-Host "Command: $removeCmd" -ForegroundColor Gray
            
            if (-not $DryRun) {
                $removeResult = Invoke-Expression $removeCmd
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "[ERROR] Failed to remove targets" -ForegroundColor Red
                    Write-Host $removeResult
                    exit 1
                }
                
                $removeData = $removeResult | ConvertFrom-Json
                if ($removeData.FailedEntryCount -gt 0) {
                    Write-Host "[WARNING] Some targets failed to be removed:" -ForegroundColor Yellow
                    $removeData.FailedEntries | ForEach-Object {
                        Write-Host "  Target $($_.TargetId): $($_.ErrorMessage)" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "[SUCCESS] All targets removed successfully" -ForegroundColor Green
                }
                
                # Wait for targets to be fully removed
                Write-Host ""
                Write-Host "Step 3: Waiting for targets to be fully removed..." -ForegroundColor Blue
                Start-Sleep -Seconds 5
            } else {
                Write-Host "[DRYRUN] Would remove targets: $targetIdString" -ForegroundColor Yellow
            }
        }
        
        # Step 3: Delete the rule
        Write-Host ""
        Write-Host "Step 4: Deleting rule '$RuleName'..." -ForegroundColor Blue
        $deleteCmd = "aws events delete-rule --name `"$RuleName`" --region $Region"
        Write-Host "Command: $deleteCmd" -ForegroundColor Gray
        
        if (-not $DryRun) {
            $deleteResult = Invoke-Expression $deleteCmd
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[SUCCESS] Rule '$RuleName' deleted successfully!" -ForegroundColor Green
            } else {
                Write-Host "[ERROR] Failed to delete rule" -ForegroundColor Red
                Write-Host $deleteResult
                exit 1
            }
        } else {
            Write-Host "[DRYRUN] Would delete rule: $RuleName" -ForegroundColor Yellow
        }
        
        Write-Host ""
        Write-Host "✅ CLEANUP COMPLETED SUCCESSFULLY!" -ForegroundColor Green
        Write-Host "You can now re-run your Cloud Custodian cleanup process." -ForegroundColor White
        
    } catch {
        Write-Host "[ERROR] Exception occurred: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
    
} else {
    # Provide manual instructions
    Write-Host ""
    Write-Host "AWS CLI NOT AVAILABLE - MANUAL STEPS REQUIRED:" -ForegroundColor Red
    Write-Host "-" * 50 -ForegroundColor Gray
    Write-Host ""
    Write-Host "OPTION 1: Install AWS CLI and run this script again" -ForegroundColor Cyan
    Write-Host "Download from: https://aws.amazon.com/cli/" -ForegroundColor Gray
    Write-Host ""
    Write-Host "OPTION 2: Use AWS Console (Recommended)" -ForegroundColor Cyan
    Write-Host "1. Go to: https://console.aws.amazon.com/cloudwatch/home?region=$Region#events:" -ForegroundColor White
    Write-Host "2. Click on 'Rules' in the left sidebar" -ForegroundColor White
    Write-Host "3. Find and click on rule: '$RuleName'" -ForegroundColor White
    Write-Host "4. Go to the 'Targets' tab" -ForegroundColor White
    Write-Host "5. Select all targets and click 'Remove'" -ForegroundColor White
    Write-Host "6. Go back to Rules list and delete the rule" -ForegroundColor White
    Write-Host ""
    Write-Host "OPTION 3: Install AWS PowerShell Module" -ForegroundColor Cyan
    Write-Host "Run: Install-Module -Name AWS.Tools.CloudWatchEvents -Force" -ForegroundColor Gray
    Write-Host "Then use AWS PowerShell commands" -ForegroundColor Gray
    Write-Host ""
}

Write-Host ""
Write-Host "=" * 70 -ForegroundColor Blue