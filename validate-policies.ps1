# Cloud Custodian Policy Validation Script
# This script helps validate Cloud Custodian policies locally

Write-Host "🔍 Cloud Custodian Policy Validation" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

# Check if Python is available
$pythonCmd = $null
$pythonCommands = @("python", "python3", "py")

foreach ($cmd in $pythonCommands) {
    try {
        $version = & $cmd --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            $pythonCmd = $cmd
            Write-Host "✅ Found Python: $version" -ForegroundColor Green
            break
        }
    } catch {
        # Continue to next command
    }
}

if (-not $pythonCmd) {
    Write-Host "❌ Python not found. Please install Python first:" -ForegroundColor Red
    Write-Host "   1. Download from: https://www.python.org/downloads/" -ForegroundColor Yellow
    Write-Host "   2. Make sure to check 'Add Python to PATH' during installation" -ForegroundColor Yellow
    Write-Host "   3. Restart PowerShell after installation" -ForegroundColor Yellow
    exit 1
}

# Check if Cloud Custodian is installed
Write-Host "`n📦 Checking Cloud Custodian installation..." -ForegroundColor Cyan
try {
    $c7nVersion = & $pythonCmd -m c7n version 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Cloud Custodian is installed: $c7nVersion" -ForegroundColor Green
    } else {
        throw "Not installed"
    }
} catch {
    Write-Host "📥 Installing Cloud Custodian..." -ForegroundColor Yellow
    & $pythonCmd -m pip install c7n
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to install Cloud Custodian" -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ Cloud Custodian installed successfully" -ForegroundColor Green
}

# Validate policy files
Write-Host "`n🔍 Validating policy files..." -ForegroundColor Cyan
$policyFiles = Get-ChildItem -Path "policies\*.yml" -File

foreach ($file in $policyFiles) {
    Write-Host "   Validating $($file.Name)..." -ForegroundColor Gray
    
    try {
        & $pythonCmd -m c7n validate $file.FullName 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "   ✅ $($file.Name) is valid" -ForegroundColor Green
        } else {
            Write-Host "   ❌ $($file.Name) has validation errors" -ForegroundColor Red
            # Run again to show errors
            & $pythonCmd -m c7n validate $file.FullName
        }
    } catch {
        Write-Host "   ❌ Error validating $($file.Name)" -ForegroundColor Red
    }
}

Write-Host "`n🎉 Validation complete!" -ForegroundColor Cyan