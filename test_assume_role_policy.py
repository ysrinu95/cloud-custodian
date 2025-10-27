#!/usr/bin/env python3
"""
Test running Cloud Custodian policies with AssumeRole like c7n-org does
"""

import boto3
import yaml
import tempfile
import subprocess
import os
import sys
from botocore.exceptions import ClientError

def load_accounts_config():
    """Load the accounts.yml configuration"""
    with open('c7n/config/accounts.yml', 'r') as f:
        config = yaml.safe_load(f)
    return config['accounts'][0]  # Get first account

def run_policy_with_assume_role(policy_file, account_config):
    """Run a policy using AssumeRole like c7n-org would"""
    
    print(f"🔍 Testing policy: {policy_file}")
    print(f"   Account: {account_config['name']} ({account_config['account_id']})")
    print(f"   Role: {account_config['role']}")
    print(f"   Region: {account_config['regions'][0]}")
    
    try:
        # Create STS client
        sts = boto3.client('sts')
        
        # Assume the role
        response = sts.assume_role(
            RoleArn=account_config['role'],
            RoleSessionName=f"test-c7n-{account_config['name']}"
        )
        
        credentials = response['Credentials']
        print("✅ Successfully assumed role")
        
        # Set up environment variables for AWS credentials
        env = os.environ.copy()
        env.update({
            'AWS_ACCESS_KEY_ID': credentials['AccessKeyId'],
            'AWS_SECRET_ACCESS_KEY': credentials['SecretAccessKey'],
            'AWS_SESSION_TOKEN': credentials['SessionToken'],
            'AWS_DEFAULT_REGION': account_config['regions'][0]
        })
        
        # Run custodian with the assumed role credentials
        cmd = [
            sys.executable, '-m', 'c7n.cli', 'run',
            '--dryrun',
            '-s', 'output_test',
            '--region', account_config['regions'][0],
            policy_file
        ]
        
        print(f"🔧 Running command: {' '.join(cmd)}")
        
        result = subprocess.run(
            cmd,
            env=env,
            capture_output=True,
            text=True,
            timeout=60
        )
        
        if result.returncode == 0:
            print("✅ Policy execution successful!")
            print("📋 Output:")
            print(result.stdout)
            return True
        else:
            print("❌ Policy execution failed!")
            print("📋 Error output:")
            print(result.stderr)
            print("📋 Standard output:")
            print(result.stdout)
            return False
            
    except ClientError as e:
        print(f"❌ AssumeRole failed: {e}")
        return False
    except subprocess.TimeoutExpired:
        print("❌ Policy execution timed out")
        return False
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return False

def main():
    print("🔍 Testing Cloud Custodian Policy with AssumeRole")
    print("=" * 60)
    
    # Load account configuration
    try:
        account = load_accounts_config()
    except Exception as e:
        print(f"❌ Error loading accounts.yml: {e}")
        return
    
    # Test the CloudWatch policy that's failing
    policy_file = 'test_cloudwatch.yml'
    success = run_policy_with_assume_role(policy_file, account)
    
    print("\n" + "=" * 60)
    if success:
        print("✅ Test passed - policy works with AssumeRole")
        print("💡 If c7n-org still fails, the issue might be:")
        print("   - c7n-org specific configuration")
        print("   - Different policy file format expectations")
        print("   - c7n-org version compatibility")
    else:
        print("❌ Test failed - this matches the c7n-org behavior")

if __name__ == "__main__":
    main()