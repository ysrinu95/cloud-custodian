# Install Terraform and AWS CLI
# This script downloads and installs Terraform and AWS CLI

Write-Host "Installing Terraform and AWS CLI..." -ForegroundColor Green

# Create a tools directory
$toolsDir = "$env:USERPROFILE\tools"
if (!(Test-Path $toolsDir)) {
    New-Item -ItemType Directory -Path $toolsDir -Force
}

# Install Terraform
Write-Host "Downloading Terraform..." -ForegroundColor Yellow
$terraformVersion = "1.6.0"
$terraformUrl = "https://releases.hashicorp.com/terraform/$terraformVersion/terraform_${terraformVersion}_windows_amd64.zip"
$terraformZip = "$toolsDir\terraform.zip"

try {
    Invoke-WebRequest -Uri $terraformUrl -OutFile $terraformZip -UseBasicParsing
    Expand-Archive -Path $terraformZip -DestinationPath $toolsDir -Force
    Remove-Item $terraformZip
    Write-Host "Terraform downloaded successfully" -ForegroundColor Green
} catch {
    Write-Host "Failed to download Terraform: $_" -ForegroundColor Red
}

# Install AWS CLI
Write-Host "Downloading AWS CLI..." -ForegroundColor Yellow
$awsCliUrl = "https://awscli.amazonaws.com/AWSCLIV2.msi"
$awsCliMsi = "$toolsDir\AWSCLIV2.msi"

try {
    Invoke-WebRequest -Uri $awsCliUrl -OutFile $awsCliMsi -UseBasicParsing
    Write-Host "AWS CLI downloaded. Installing..." -ForegroundColor Yellow
    Start-Process msiexec.exe -Wait -ArgumentList "/i `"$awsCliMsi`" /quiet"
    Remove-Item $awsCliMsi
    Write-Host "AWS CLI installed successfully" -ForegroundColor Green
} catch {
    Write-Host "Failed to download/install AWS CLI: $_" -ForegroundColor Red
}

# Add tools to PATH temporarily
$env:PATH = "$toolsDir;$env:PATH"

Write-Host "Installation complete!" -ForegroundColor Green
Write-Host "Please restart your PowerShell session or add $toolsDir to your PATH environment variable" -ForegroundColor Yellow
Write-Host "Then run: terraform --version and aws --version to verify installation" -ForegroundColor Yellow