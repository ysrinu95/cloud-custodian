#!/usr/bin/env python3
"""
Simulate c7n-org behavior to debug the exact issue
"""

import boto3
import yaml
import json
from botocore.exceptions import ClientError

def load_accounts_config():
    """Load the accounts.yml configuration"""
    try:
        with open('c7n/config/accounts.yml', 'r') as f:
            config = yaml.safe_load(f)
        return config['accounts']
    except Exception as e:
        print(f"❌ Error loading accounts.yml: {e}")
        return None

def test_cross_account_assume(account_config):
    """Test assuming role as c7n-org would do it"""
    account_id = account_config['account_id']
    role_arn = account_config['role']
    regions = account_config['regions']
    
    print(f"🔍 Testing account: {account_config['name']}")
    print(f"   Account ID: {account_id}")
    print(f"   Role ARN: {role_arn}")
    print(f"   Regions: {regions}")
    
    try:
        # Create STS client
        sts = boto3.client('sts')
        
        # Assume the role
        response = sts.assume_role(
            RoleArn=role_arn,
            RoleSessionName=f"c7n-org-test-{account_config['name']}"
        )
        
        credentials = response['Credentials']
        print("✅ Successfully assumed role")
        
        # Test creating sessions for each region
        for region in regions:
            try:
                # Create session with assumed role credentials
                session = boto3.Session(
                    aws_access_key_id=credentials['AccessKeyId'],
                    aws_secret_access_key=credentials['SecretAccessKey'],
                    aws_session_token=credentials['SessionToken'],
                    region_name=region
                )
                
                # Test a simple AWS call (like c7n would do)
                ec2 = session.client('ec2')
                ec2.describe_regions()  # Simple test call
                
                print(f"✅ Region {region}: Session working")
                
            except ClientError as e:
                print(f"❌ Region {region}: {e}")
                return False
            except Exception as e:
                print(f"❌ Region {region}: Unexpected error: {e}")
                return False
        
        return True
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        print(f"❌ AssumeRole failed:")
        print(f"   Error Code: {error_code}")
        print(f"   Error Message: {error_message}")
        return False
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return False

def test_policy_validation():
    """Test if policies can be loaded without errors"""
    import os
    import glob
    
    policy_files = glob.glob('c7n/policies/*.yml')
    print(f"\n🔍 Testing {len(policy_files)} policy files for YAML syntax...")
    
    for policy_file in policy_files:
        try:
            with open(policy_file, 'r') as f:
                yaml.safe_load(f)
            print(f"✅ {os.path.basename(policy_file)}: Valid YAML")
        except yaml.YAMLError as e:
            print(f"❌ {os.path.basename(policy_file)}: YAML Error: {e}")
            return False
        except Exception as e:
            print(f"❌ {os.path.basename(policy_file)}: Error: {e}")
            return False
    
    return True

def main():
    print("🔍 C7N-ORG AssumeRole Simulation Test")
    print("=" * 60)
    
    # Load accounts configuration
    accounts = load_accounts_config()
    if not accounts:
        return
    
    print(f"📋 Loaded {len(accounts)} account(s) from accounts.yml")
    
    # Test each account
    all_passed = True
    for account in accounts:
        print("\n" + "-" * 40)
        success = test_cross_account_assume(account)
        if not success:
            all_passed = False
    
    print("\n" + "=" * 60)
    
    # Test policy files
    policy_success = test_policy_validation()
    
    print("\n" + "=" * 60)
    print("🏁 Final Results:")
    
    if all_passed and policy_success:
        print("✅ All tests passed - c7n-org should work!")
        print("💡 If c7n-org still fails, the issue might be:")
        print("   - c7n-org version incompatibility")
        print("   - Different AWS session configuration")
        print("   - Specific policy resource permissions")
    else:
        print("❌ Tests failed - this explains the c7n-org issues")

if __name__ == "__main__":
    main()