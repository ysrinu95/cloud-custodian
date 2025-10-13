# GitHub Secret Configuration Guide

## 🔑 Required GitHub Secret

After the bootstrap process, you need to add the AWS Role ARN as a GitHub secret for OIDC authentication.

### Step 1: Add GitHub Repository Secret

1. **Go to your GitHub repository**: https://github.com/ysrinu95/cloud-custodian
2. **Click on "Settings"** (in the repository navigation)
3. **Click on "Secrets and variables"** → **"Actions"**
4. **Click "New repository secret"**
5. **Add the following secret**:
   - **Name**: `AWS_ROLE_ARN`
   - **Value**: `arn:aws:iam::172327596604:role/GitHubActions-CloudCustodian-Role`
6. **Click "Add secret"**

### Step 2: Verify OIDC Setup

Once the secret is added, the Cloud Custodian workflows will use OIDC authentication instead of access keys.

## 🛡️ Security Benefits

✅ **No long-term credentials** stored in GitHub
✅ **Temporary credentials** generated for each workflow run
✅ **Role-based access** with least privilege
✅ **Audit trail** through AWS CloudTrail
✅ **Automatic credential rotation**

## 🚀 Available Workflows

### 1. Cloud Custodian Operations
- **Path**: `.github/workflows/cloud-custodian.yml`
- **Purpose**: Run Cloud Custodian policies
- **Actions**: validate, dryrun, run
- **Authentication**: OIDC with AWS Role

### 2. Terraform Infrastructure
- **Path**: `.github/workflows/terraform.yml`
- **Purpose**: Deploy infrastructure changes
- **Actions**: plan, apply, destroy
- **Authentication**: OIDC with AWS Role

### 3. Bootstrap OIDC (One-time)
- **Path**: `.github/workflows/bootstrap-oidc.yml`
- **Purpose**: Create OIDC provider and IAM role
- **Status**: ✅ Already completed
- **Authentication**: Access keys (bootstrap only)

## 🧹 Cleanup Old Secrets

After confirming OIDC works, you can safely delete these old secrets:
- `ACCESS_KEY` (if exists)
- `SECRET_ACCESS_KEY` (if exists)

## 🔍 Testing OIDC Setup

Run the Cloud Custodian workflow to test:
1. Go to **Actions** → **"Cloud Custodian Operations"**
2. Click **"Run workflow"**
3. Select **"validate"** action
4. Click **"Run workflow"**

If successful, your OIDC authentication is working! 🎉