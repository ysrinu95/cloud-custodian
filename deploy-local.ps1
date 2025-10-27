# Local Cloud Custodian Policy Deployment Script
# This script deploys policies locally without using c7n-org to avoid AssumeRole issues

param(
    [switch]$DryRun = $true,
    [string]$OutputDir = "output_local",
    [string[]]$PolicyFiles = @(
        "c7n\policies\cloudwatch.yml",
        "c7n\policies\ec2.yml", 
        "c7n\policies\lambda.yml",
        "c7n\policies\rds.yml",
        "c7n\policies\s3.yml",
        "c7n\policies\security-findings.yml",
        "c7n\policies\ec2-public-stepfunction.yml"
    )
)

Write-Host "Cloud Custodian Local Deployment" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "Running in DRY RUN mode" -ForegroundColor Yellow
} else {
    Write-Host "Running in LIVE DEPLOYMENT mode" -ForegroundColor Red
}

$SuccessCount = 0
$TotalCount = $PolicyFiles.Count

foreach ($PolicyFile in $PolicyFiles) {
    if (Test-Path $PolicyFile) {
        Write-Host "`nDeploying $PolicyFile..." -ForegroundColor Green
        
        $cmd = @("python", "-m", "c7n.cli", "run", "-s", $OutputDir, $PolicyFile)
        if ($DryRun) {
            $cmd += "--dryrun"
        }
        
        Write-Host "Command: $($cmd -join ' ')" -ForegroundColor Gray
        
        try {
            & $cmd[0] $cmd[1..($cmd.Length-1)]
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ $PolicyFile deployed successfully" -ForegroundColor Green
                $SuccessCount++
            } else {
                Write-Host "❌ $PolicyFile failed with exit code $LASTEXITCODE" -ForegroundColor Red
            }
        }
        catch {
            Write-Host "❌ Error deploying $PolicyFile : $_" -ForegroundColor Red
        }
    } else {
        Write-Host "⚠️  $PolicyFile not found" -ForegroundColor Yellow
    }
}

Write-Host "`n=================================" -ForegroundColor Cyan
Write-Host "Deployment Summary: $SuccessCount/$TotalCount policies deployed successfully" -ForegroundColor Cyan

if ($SuccessCount -eq $TotalCount) {
    Write-Host "🎉 All policies deployed successfully!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "⚠️  Some policies failed to deploy" -ForegroundColor Yellow
    exit 1
}