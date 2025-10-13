# Cloud Custodian Policy Validation Script
Write-Host "🔍 Cloud Custodian Policy Validation" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

# Check if Python is available
$pythonCmd = $null
$pythonCommands = @("python", "python3", "py")

foreach ($cmd in $pythonCommands) {
    try {
        $version = & $cmd --version 2>&1
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

# Install Cloud Custodian if not available
Write-Host "`n📦 Installing/Checking Cloud Custodian..." -ForegroundColor Cyan
& $pythonCmd -m pip install c7n --quiet
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Cloud Custodian is ready" -ForegroundColor Green
} else {
    Write-Host "❌ Failed to install Cloud Custodian" -ForegroundColor Red
    exit 1
}

# Validate policy files
Write-Host "`n🔍 Validating policy files..." -ForegroundColor Cyan
$policyFiles = Get-ChildItem -Path "policies\*.yml" -File

foreach ($file in $policyFiles) {
    Write-Host "   Validating $($file.Name)..." -ForegroundColor Gray
    
    $output = & $pythonCmd -m c7n validate $file.FullName 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   ✅ $($file.Name) is valid" -ForegroundColor Green
    } else {
        Write-Host "   ❌ $($file.Name) has validation errors:" -ForegroundColor Red
        Write-Host $output -ForegroundColor Red
    }
}

Write-Host "`nValidation complete!" -ForegroundColor Cyan