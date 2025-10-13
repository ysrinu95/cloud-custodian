# cloud-custodian

Implementation of the [Cloud Custodian](https://cloudcustodian.io) (c7n) application.

## Overview

### infrastructure

Core AWS infrastructure needed for c7n to run and respond to policies.

### policies

c7n policy definitions.

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

1. Install necessary package prerequisites.
    ```sh
    cd c7n
    pip install -r requirements.txt
    ```
2. Generate AWS credentials to a profile.
3. Temporarily modify `c7n/config/accounts.yml` to swap `profile` for `role` under the account you wish to run c7n against.
4. Run your desired `c7n-org` commands with the `--dryrun` flag. Examples can be found at the bottom of each file in `c7n/scripts`.
