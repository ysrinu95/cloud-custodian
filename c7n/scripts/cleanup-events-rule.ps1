# cleanup-events-rule.ps1 - PowerShell script to clean up CloudWatch Events rules with targets
# Usage: .\cleanup-events-rule.ps1 -RuleName "custodian-ebs-unencrypted-volumes-scheduled" [-Profile "profile"] [-Region "region"] [-DryRun]

param(
    [Parameter(Mandatory=$true)]
    [string]$RuleName,
    
    [Parameter(Mandatory=$false)]
    [string]$Profile = "",
    
    [Parameter(Mandatory=$false)]
    [string]$Region = "us-east-1",
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun = $false
)

# Colors for output
function Write-Status {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Build AWS CLI command prefix
$AwsCmd = "aws events"
if ($Profile) {
    $AwsCmd += " --profile $Profile"
}
$AwsCmd += " --region $Region"

function Test-RuleExists {
    param([string]$RuleName)
    
    Write-Status "Checking if rule '$RuleName' exists..."
    
    try {
        $result = Invoke-Expression "$AwsCmd describe-rule --name `"$RuleName`"" 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Rule '$RuleName' found"
            return $true
        }
    }
    catch {
        Write-Warning "Rule '$RuleName' not found"
        return $false
    }
    
    Write-Warning "Rule '$RuleName' not found"
    return $false
}

function Remove-RuleTargets {
    param([string]$RuleName)
    
    Write-Status "Listing targets for rule '$RuleName'..."
    
    try {
        $targetsJson = Invoke-Expression "$AwsCmd list-targets-by-rule --rule `"$RuleName`""
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to list targets for rule '$RuleName'"
            return $false
        }
        
        $targets = $targetsJson | ConvertFrom-Json
        
        if (-not $targets.Targets -or $targets.Targets.Count -eq 0) {
            Write-Status "No targets found for rule '$RuleName'"
            return $true
        }
        
        $targetIds = $targets.Targets | ForEach-Object { $_.Id }
        $targetIdString = $targetIds -join " "
        
        Write-Status "Found targets: $targetIdString"
        
        if ($DryRun) {
            Write-Warning "DRYRUN: Would remove targets: $targetIdString"
            return $true
        }
        
        Write-Status "Removing targets from rule '$RuleName'..."
        
        $removeResult = Invoke-Expression "$AwsCmd remove-targets --rule `"$RuleName`" --ids $targetIdString"
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Successfully removed targets from rule '$RuleName'"
            
            $removeData = $removeResult | ConvertFrom-Json
            if ($removeData.FailedEntryCount -gt 0) {
                Write-Warning "Some targets failed to be removed (FailedEntryCount: $($removeData.FailedEntryCount))"
                Write-Host $removeResult
                return $false
            }
            
            return $true
        }
        else {
            Write-Error "Failed to remove targets from rule '$RuleName'"
            Write-Host $removeResult
            return $false
        }
    }
    catch {
        Write-Error "Error removing targets: $($_.Exception.Message)"
        return $false
    }
}

function Remove-Rule {
    param([string]$RuleName)
    
    Write-Status "Deleting rule '$RuleName'..."
    
    if ($DryRun) {
        Write-Warning "DRYRUN: Would delete rule '$RuleName'"
        return $true
    }
    
    try {
        $deleteResult = Invoke-Expression "$AwsCmd delete-rule --name `"$RuleName`""
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Successfully deleted rule '$RuleName'"
            return $true
        }
        else {
            Write-Error "Failed to delete rule '$RuleName'"
            Write-Host $deleteResult
            return $false
        }
    }
    catch {
        Write-Error "Error deleting rule: $($_.Exception.Message)"
        return $false
    }
}

# Main execution
function Main {
    Write-Status "Starting CloudWatch Events rule cleanup..."
    Write-Status "Rule: $RuleName"
    Write-Status "Region: $Region"
    if ($Profile) {
        Write-Status "Profile: $Profile"
    }
    if ($DryRun) {
        Write-Warning "DRYRUN MODE: No changes will be made"
    }
    Write-Host ""
    
    # Check if AWS CLI is available
    try {
        $null = Get-Command aws -ErrorAction Stop
    }
    catch {
        Write-Error "AWS CLI not found. Please install it first."
        exit 1
    }
    
    # Step 1: Check if rule exists
    if (-not (Test-RuleExists $RuleName)) {
        Write-Warning "Rule '$RuleName' does not exist. Nothing to clean up."
        exit 0
    }
    
    # Step 2: Remove targets
    if (-not (Remove-RuleTargets $RuleName)) {
        Write-Error "Failed to remove targets. Cannot proceed with rule deletion."
        exit 1
    }
    
    # Wait a moment for targets to be fully removed
    if (-not $DryRun) {
        Write-Status "Waiting for targets to be fully removed..."
        Start-Sleep -Seconds 3
    }
    
    # Step 3: Delete the rule
    if (-not (Remove-Rule $RuleName)) {
        Write-Error "Failed to delete rule '$RuleName'"
        exit 1
    }
    
    Write-Host ""
    Write-Success "✅ CloudWatch Events rule cleanup completed successfully!"
    
    if (-not $DryRun) {
        Write-Status "Rule '$RuleName' has been completely removed"
    }
    else {
        Write-Status "DRYRUN completed - no actual changes were made"
    }
}

# Run main function
Main