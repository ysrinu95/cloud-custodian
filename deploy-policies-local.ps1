# Simple Cloud Custodian Local Deployment Script
# Deploys policies individually and skips problematic ones

param(
    [switch]$Live,  # Use -Live for actual deployment, default is dry-run
    [string]$Region = "us-east-1"
)

$DryRun = -not $Live

Write-Host "🚀 Cloud Custodian Local Deployment" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "Running in DRY RUN mode" -ForegroundColor Yellow
} else {
    Write-Host "Running in LIVE DEPLOYMENT mode" -ForegroundColor Red
    $confirm = Read-Host "Are you sure you want to deploy policies LIVE? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "Deployment cancelled" -ForegroundColor Yellow
        exit 0
    }
}

Write-Host "Target Region: $Region" -ForegroundColor Cyan

# Simple policies that work reliably
$SafePolicies = @(
    @{File="c7n\policies\cloudwatch.yml"; Name="CloudWatch Log Group Management"},
    @{File="c7n\policies\ec2.yml"; Name="EC2 Public IP and Security Group Monitoring"},
    @{File="c7n\policies\lambda.yml"; Name="Lambda Runtime Management"},
    @{File="c7n\policies\rds.yml"; Name="RDS Database Management"},
    @{File="c7n\policies\s3.yml"; Name="S3 Bucket Security"},
    @{File="c7n\policies\ec2-public-stepfunction.yml"; Name="EC2 Public Instance Step Functions"}
)

$SuccessCount = 0
$TotalCount = $SafePolicies.Count

foreach ($Policy in $SafePolicies) {
    Write-Host "`n📋 Deploying: $($Policy.Name)" -ForegroundColor Green
    
    $cmd = @("python", "-m", "c7n.cli", "run", "-s", "output_local", "--region", $Region, $Policy.File)
    if ($DryRun) {
        $cmd += "--dryrun"
    }
    
    Write-Host "Command: $($cmd -join ' ')" -ForegroundColor Gray
    
    try {
        & $cmd[0] $cmd[1..($cmd.Length-1)]
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ $($Policy.Name) deployed successfully" -ForegroundColor Green
            $SuccessCount++
        } else {
            Write-Host "❌ $($Policy.Name) failed with exit code $LASTEXITCODE" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "❌ Error deploying $($Policy.Name): $_" -ForegroundColor Red
    }
}

Write-Host "`n====================================" -ForegroundColor Cyan
Write-Host "📊 Deployment Summary: $SuccessCount/$TotalCount policies deployed successfully" -ForegroundColor Cyan

if ($SuccessCount -eq $TotalCount) {
    Write-Host "🎉 All policies deployed successfully!" -ForegroundColor Green
    Write-Host "`nNote: Security Hub policies were skipped (service not subscribed)" -ForegroundColor Yellow
} else {
    Write-Host "⚠️  Some policies failed to deploy" -ForegroundColor Yellow
}

Write-Host "`n💡 To deploy Security Hub policies, first subscribe to AWS Security Hub in your account" -ForegroundColor Cyan