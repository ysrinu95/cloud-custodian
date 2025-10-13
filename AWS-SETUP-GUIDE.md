# AWS Credentials Setup for Terraform

Since the S3 bucket already exists, you have two options to complete the bootstrap process:

## Option 1: Use GitHub Actions (Recommended)

This is the safest and most secure approach since your AWS credentials are already configured in GitHub.

### Steps:
1. **Commit and push your changes:**
   ```powershell
   cd "c:\United Techno\Git Repos\cloud-custodian"
   git add .
   git commit -m "Update terraform-bootstrap for remote state with S3 backend"
   git push origin main
   ```

2. **Run the Bootstrap Workflow:**
   - Go to your GitHub repository: https://github.com/ysrinu95/cloud-custodian
   - Click on "Actions" tab
   - Find "Bootstrap OIDC Authentication" workflow
   - Click "Run workflow"
   - Type `bootstrap` in the confirmation field
   - ✅ Check `cleanup_existing` if you want to clean up existing resources first
   - Click "Run workflow"

3. **The workflow will:**
   - Use your existing S3 bucket
   - Initialize Terraform with remote state
   - Clean up existing resources (if selected)
   - Create fresh resources with proper state tracking
   - Provide the new AWS Role ARN for GitHub secrets

## Option 2: Local Setup (Manual)

If you want to run Terraform locally, you need to configure AWS credentials first.

### Install AWS CLI:
```powershell
# Download AWS CLI v2
$awsCliUrl = "https://awscli.amazonaws.com/AWSCLIV2.msi"
$awsCliMsi = "$env:TEMP\AWSCLIV2.msi"
Invoke-WebRequest -Uri $awsCliUrl -OutFile $awsCliMsi
Start-Process msiexec.exe -Wait -ArgumentList "/i `"$awsCliMsi`" /quiet"
```

### Configure AWS Credentials:
```powershell
# After installing AWS CLI, restart PowerShell and run:
aws configure
# Enter your:
# - AWS Access Key ID
# - AWS Secret Access Key
# - Default region: us-east-1
# - Default output format: json
```

### Initialize Terraform:
```powershell
cd "c:\United Techno\Git Repos\cloud-custodian\terraform-bootstrap"
$env:PATH = "$env:USERPROFILE\tools;$env:PATH"
terraform init
terraform plan
terraform apply
```

## Recommendation

**Use Option 1 (GitHub Actions)** because:
- ✅ Your AWS credentials are already configured in GitHub
- ✅ No need to expose credentials on your local machine
- ✅ The workflow includes automatic cleanup and error handling
- ✅ State is immediately stored in S3 with proper tracking
- ✅ More secure and follows best practices

The GitHub Actions workflow will handle everything automatically and securely!