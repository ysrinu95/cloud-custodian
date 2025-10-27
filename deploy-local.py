#!/usr/bin/env python3
"""
Local deployment script for Cloud Custodian policies.
This script deploys policies directly without c7n-org to avoid AssumeRole issues.
"""

import os
import subprocess
import sys
from pathlib import Path

def run_custodian_policy(policy_file, output_dir="output_local", dryrun=True):
    """Run a single custodian policy locally"""
    cmd = [
        "custodian", "run",
        "-s", output_dir,
        policy_file
    ]
    
    if dryrun:
        cmd.append("--dryrun")
    
    print(f"Running: {' '.join(cmd)}")
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, cwd=os.getcwd())
        print(f"STDOUT: {result.stdout}")
        if result.stderr:
            print(f"STDERR: {result.stderr}")
        return result.returncode == 0
    except Exception as e:
        print(f"Error running command: {e}")
        return False

def main():
    """Deploy all policies locally"""
    policy_dir = Path("c7n/policies")
    policy_files = [
        "cloudwatch.yml",
        "ec2.yml", 
        "lambda.yml",
        "rds.yml",
        "s3.yml",
        "security-findings.yml",
        "ec2-public-stepfunction.yml"
    ]
    
    # Check if we want dry-run or actual deployment
    dryrun = "--dryrun" in sys.argv or "-d" in sys.argv
    
    print(f"Deploying policies locally {'(DRY RUN)' if dryrun else '(LIVE DEPLOYMENT)'}")
    print("=" * 60)
    
    success_count = 0
    total_count = len(policy_files)
    
    for policy_file in policy_files:
        policy_path = policy_dir / policy_file
        if policy_path.exists():
            print(f"\n🚀 Deploying {policy_file}...")
            if run_custodian_policy(str(policy_path), dryrun=dryrun):
                print(f"✅ {policy_file} deployed successfully")
                success_count += 1
            else:
                print(f"❌ {policy_file} failed to deploy")
        else:
            print(f"⚠️  {policy_file} not found")
    
    print("\n" + "=" * 60)
    print(f"Deployment Summary: {success_count}/{total_count} policies deployed successfully")
    
    if success_count == total_count:
        print("🎉 All policies deployed successfully!")
        return 0
    else:
        print("⚠️  Some policies failed to deploy")
        return 1

if __name__ == "__main__":
    sys.exit(main())