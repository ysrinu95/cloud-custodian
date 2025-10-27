# Simple Cloud Custodian Local Deployment Script
# Deploys policies individually and skips problematic ones

param(
    [switch]$Live,
    [string]$Region = "us-east-1"
)

$DryRun = -not $Live

Write-Host "Cloud Custodian Local Deployment" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "Running in DRY RUN mode" -ForegroundColor Yellow
} else {
    Write-Host "Running in LIVE DEPLOYMENT mode" -ForegroundColor Red
}

Write-Host "Target Region: $Region" -ForegroundColor Cyan

# Policies to deploy
$PolicyFiles = @(
    "c7n\policies\cloudwatch.yml",
    "c7n\policies\ec2.yml", 
    "c7n\policies\lambda.yml",
    "c7n\policies\rds.yml",
    "c7n\policies\s3.yml",
    "c7n\policies\ec2-public-stepfunction.yml"
)

$SuccessCount = 0
$TotalCount = $PolicyFiles.Count

foreach ($PolicyFile in $PolicyFiles) {
    Write-Host "`nDeploying $PolicyFile..." -ForegroundColor Green
    
    $cmd = @("python", "-m", "c7n.cli", "run", "-s", "output_local", "--region", $Region, $PolicyFile)
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
}

Write-Host "`n=================================" -ForegroundColor Cyan
Write-Host "Deployment Summary: $SuccessCount/$TotalCount policies deployed successfully" -ForegroundColor Cyan

if ($SuccessCount -eq $TotalCount) {
    Write-Host "🎉 All policies deployed successfully!" -ForegroundColor Green
} else {
    Write-Host "⚠️  Some policies failed to deploy" -ForegroundColor Yellow
}