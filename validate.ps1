# Cloud Custodian Policy Validation Script
Write-Host "Cloud Custodian Policy Validation" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan

# Check if Python is available
$pythonCmd = $null
$pythonCommands = @("python", "python3", "py")

foreach ($cmd in $pythonCommands) {
    try {
        $null = & $cmd --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            $pythonCmd = $cmd
            Write-Host "Found Python: $cmd" -ForegroundColor Green
            break
        }
    } catch {
        # Continue to next command
    }
}

if (-not $pythonCmd) {
    Write-Host "Python not found. Please install Python first." -ForegroundColor Red
    exit 1
}

# Install Cloud Custodian if not available
Write-Host "Installing/Checking Cloud Custodian..." -ForegroundColor Cyan
& $pythonCmd -m pip install c7n --quiet --disable-pip-version-check
Write-Host "Cloud Custodian is ready" -ForegroundColor Green

# Validate policy files
Write-Host "Validating policy files..." -ForegroundColor Cyan
$policyFiles = Get-ChildItem -Path "policies\*.yml" -File

foreach ($file in $policyFiles) {
    Write-Host "Validating $($file.Name)..." -ForegroundColor Gray
    
    $output = & $pythonCmd -c "
import sys
sys.path.insert(0, '.')
try:
    from c7n.commands import validate
    result = validate(['$($file.FullName)'])
    sys.exit(0 if result else 1)
except Exception as e:
    print(f'Error: {e}')
    sys.exit(1)
" 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "$($file.Name) is VALID" -ForegroundColor Green
    } else {
        Write-Host "$($file.Name) has ERRORS:" -ForegroundColor Red
        Write-Host $output -ForegroundColor Red
    }
}

Write-Host "Validation complete!" -ForegroundColor Cyan