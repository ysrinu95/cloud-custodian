# cloud-custodian

Implementation of the [Cloud Custodian](https://cloudcustodian.io) (c7n) application.

## Overview

### terraform/

Core AWS infrastructure needed for c7n to run and respond to policies. This includes:
- S3 buckets for outputs and logging
- IAM roles for policy execution
- Lambda execution roles
- SNS topics for notifications
- Optional enterprise features (SQS mailer, SES)

### c7n/

Cloud Custodian implementation with:
- **c7n/policies/**: Policy definitions (both enterprise and user policies)
- **c7n/scripts/**: Deployment and management scripts
- **c7n/config/**: Configuration files and templates

## Deployment

Policies are currently handled by [c7n-org](https://cloudcustodian.io/docs/tools/c7n-org.html) and deployed to the following accounts:

* Development
* Staging
* Production
* Shared
* Audit
* Log
* Root

By default, only changed policies are deployed.

* For non-`main` branch pipeline runs (this includes PR's and topic branches), a git diff is performed against `origin/master` and the current `HEAD` to gather a list of changed policies. 
* For `main` branch pipeline runs, a git diff it performed against the current commit and the previous commit. This means that all merges into `main` **must** be either squashed or rebased into a single commit.

Additionally, there are custom pipeline steps that can be run manually to deploy all policies to the selected account. 

## Running Locally

### Prerequisites
1. Install Cloud Custodian and dependencies:
    ```sh
    pip install 'c7n>=0.9.40'
    # Optional: Install additional packages
    cd c7n
    pip install -r requirements.txt
    ```

2. Configure AWS credentials (choose one):
    - **AWS Profile**: Configure `~/.aws/credentials` or use `aws configure`
    - **Environment Variables**: Set `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
    - **IAM Role**: Use OIDC or instance roles

### Using GitHub Actions (Recommended)
1. **Manual Policy Execution**: Use "Cloud Custodian Operations" workflow
2. **Script-based Deployment**: Use "Deploy with c7n Scripts" workflow
3. **Lambda Deployment**: Use "Deploy Cloud Custodian Lambda Functions" workflow
4. **Scheduled Execution**: Automatic daily runs via "Scheduled Cloud Custodian Policies"

### Local Execution
1. **Dry Run**: Test policies without making changes
    ```sh
    custodian run --dryrun -s output/ c7n/policies/user-compliance.yml
    ```

2. **Live Execution**: Run policies with actual changes
    ```sh
    custodian run -s output/ c7n/policies/user-compliance.yml
    ```

3. **Using c7n Scripts**: For enterprise policies
    ```sh
    cd c7n
    ./scripts/deploy-policies.sh --dryrun
    ```

### Policy Development
1. **Validate**: Check policy syntax
    ```sh
    custodian validate c7n/policies/your-policy.yml
    ```

2. **Schema**: Generate AWS resource schema
    ```sh
    custodian schema aws
    ```
