# Manual Terraform Apply Instructions

Since the automatic workflow is still having issues with exit code 2, here's how to proceed manually:

## Option 1: Use GitHub Actions Manual Dispatch

1. Go to your GitHub repository: https://github.com/ysrinu95/cloud-custodian
2. Click on "Actions" tab
3. Click on "Deploy Cloud Custodian Infrastructure" workflow
4. Click "Run workflow" (on the right side)
5. Select branch: main
6. Set action to: **apply**
7. Click "Run workflow"

This will force the workflow to apply the changes even if the plan step shows exit code 2.

## Option 2: Fix the Workflow Logic

The issue is that the plan step is still failing even though we updated the logic. Let's make sure the workflow properly handles the exit code.

## Option 3: Run Terraform Locally

If the above doesn't work, you can apply the Terraform changes locally:

1. Navigate to the terraform directory
2. Run: `terraform init`
3. Run: `terraform plan` (to verify)
4. Run: `terraform apply` (to create resources)

## Why This Is Happening

The plan shows exit code 2, which means:
- ✅ Terraform plan succeeded
- ✅ Changes were detected (11 resources to create)
- ✅ Plan file was saved successfully
- ❌ GitHub Actions is incorrectly treating this as an error

The updated workflow should handle this, but there might be a caching issue or the wrong workflow version is running.