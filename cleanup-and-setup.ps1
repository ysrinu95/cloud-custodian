# AWS Resource Cleanup and Remote State Setup Script
# Run this script after configuring AWS CLI with: aws configure

Write-Host "=== Cloud Custodian Bootstrap Cleanup and Remote State Setup ===" -ForegroundColor Green

# Step 1: Check existing resources
Write-Host "`n1. Checking existing AWS resources..." -ForegroundColor Yellow

Write-Host "Checking for existing IAM role..." -ForegroundColor Cyan
aws iam get-role --role-name "GitHubActions-CloudCustodian-Role" 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Found existing IAM role: GitHubActions-CloudCustodian-Role" -ForegroundColor Red
    $hasExistingRole = $true
} else {
    Write-Host "No existing IAM role found" -ForegroundColor Green
    $hasExistingRole = $false
}

Write-Host "Checking for existing OIDC provider..." -ForegroundColor Cyan
$oidcProviders = aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[?contains(Arn, `token.actions.githubusercontent.com`)].Arn' --output text 2>$null
if ($oidcProviders) {
    Write-Host "Found existing OIDC provider: $oidcProviders" -ForegroundColor Red
    $hasExistingOIDC = $true
} else {
    Write-Host "No existing OIDC provider found" -ForegroundColor Green
    $hasExistingOIDC = $false
}

Write-Host "Checking for existing CloudCustodian policy..." -ForegroundColor Cyan
aws iam get-policy --policy-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/CloudCustodianPolicy" 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Found existing CloudCustodian policy" -ForegroundColor Red
    $hasExistingPolicy = $true
} else {
    Write-Host "No existing CloudCustodian policy found" -ForegroundColor Green
    $hasExistingPolicy = $false
}

# Step 2: Create S3 bucket for remote state
Write-Host "`n2. Creating S3 bucket for Terraform remote state..." -ForegroundColor Yellow
$bucketName = "ysr95-cloud-custodian-tf-bkt"
$region = "us-east-1"

# Check if bucket exists
aws s3 ls "s3://$bucketName" 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "S3 bucket $bucketName already exists" -ForegroundColor Yellow
} else {
    Write-Host "Creating S3 bucket: $bucketName" -ForegroundColor Cyan
    aws s3 mb "s3://$bucketName" --region $region
    
    # Enable versioning
    Write-Host "Enabling versioning on S3 bucket" -ForegroundColor Cyan
    aws s3api put-bucket-versioning --bucket $bucketName --versioning-configuration Status=Enabled
    
    # Enable encryption
    Write-Host "Enabling encryption on S3 bucket" -ForegroundColor Cyan
    aws s3api put-bucket-encryption --bucket $bucketName --server-side-encryption-configuration '{
        "Rules": [
            {
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }
        ]
    }'
    
    # Block public access
    Write-Host "Blocking public access on S3 bucket" -ForegroundColor Cyan
    aws s3api put-public-access-block --bucket $bucketName --public-access-block-configuration '{
        "BlockPublicAcls": true,
        "IgnorePublicAcls": true,
        "BlockPublicPolicy": true,
        "RestrictPublicBuckets": true
    }'
}

# Step 3: Clean up existing resources if they exist
if ($hasExistingRole -or $hasExistingOIDC -or $hasExistingPolicy) {
    Write-Host "`n3. Cleaning up existing resources..." -ForegroundColor Yellow
    
    $cleanup = Read-Host "Do you want to delete existing resources? (y/n)"
    if ($cleanup -eq 'y' -or $cleanup -eq 'Y') {
        
        if ($hasExistingRole) {
            Write-Host "Detaching policies from IAM role..." -ForegroundColor Cyan
            # Detach managed policies
            aws iam detach-role-policy --role-name "GitHubActions-CloudCustodian-Role" --policy-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/CloudCustodianPolicy" 2>$null
            aws iam detach-role-policy --role-name "GitHubActions-CloudCustodian-Role" --policy-arn "arn:aws:iam::aws:policy/ReadOnlyAccess" 2>$null
            
            Write-Host "Deleting IAM role..." -ForegroundColor Cyan
            aws iam delete-role --role-name "GitHubActions-CloudCustodian-Role"
        }
        
        if ($hasExistingPolicy) {
            Write-Host "Deleting CloudCustodian policy..." -ForegroundColor Cyan
            aws iam delete-policy --policy-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/CloudCustodianPolicy"
        }
        
        if ($hasExistingOIDC) {
            Write-Host "Deleting OIDC provider..." -ForegroundColor Cyan
            aws iam delete-open-id-connect-provider --open-id-connect-provider-arn $oidcProviders
        }
        
        Write-Host "Cleanup completed!" -ForegroundColor Green
    } else {
        Write-Host "Skipping cleanup. Please manually delete resources before proceeding." -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "`n=== Next Steps ===" -ForegroundColor Green
Write-Host "1. Update terraform-bootstrap/main.tf to enable S3 backend" -ForegroundColor White
Write-Host "2. Run: cd terraform-bootstrap && terraform init" -ForegroundColor White
Write-Host "3. Run: terraform plan && terraform apply" -ForegroundColor White
Write-Host "4. Update GitHub secrets with the new role ARN" -ForegroundColor White

Write-Host "`nS3 bucket '$bucketName' is ready for Terraform remote state!" -ForegroundColor Green