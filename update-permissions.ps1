# Update IAM Permissions Script
# Run this to update the GitHub Actions role with the additional permissions needed

Write-Host "🔧 Updating IAM permissions for Cloud Custodian infrastructure deployment..." -ForegroundColor Cyan

# Check if AWS CLI is available
try {
    aws sts get-caller-identity | Out-Null
    Write-Host "✅ AWS CLI configured and authenticated" -ForegroundColor Green
} catch {
    Write-Host "❌ AWS CLI not configured. Please configure AWS credentials first:" -ForegroundColor Red
    Write-Host "   aws configure" -ForegroundColor Yellow
    exit 1
}

# Navigate to bootstrap directory
Set-Location "terraform-bootstrap"

# Initialize Terraform
Write-Host "🔄 Initializing Terraform..." -ForegroundColor Cyan
terraform init -upgrade

# Plan the changes
Write-Host "📋 Planning permission updates..." -ForegroundColor Cyan
terraform plan -out=tfplan

# Apply the changes
Write-Host "🚀 Applying permission updates..." -ForegroundColor Cyan
terraform apply -auto-approve tfplan

Write-Host "✅ IAM permissions updated successfully!" -ForegroundColor Green
Write-Host "🔄 You can now retry the main Terraform deployment" -ForegroundColor Cyan