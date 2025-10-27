#!/usr/bin/env python3
"""
Check the actual IAM role ARN and path in AWS
"""

import boto3
import json
from botocore.exceptions import ClientError

def check_role_details():
    """Check the exact role ARN and path"""
    try:
        iam = boto3.client('iam')
        
        # Check role without path
        try:
            role = iam.get_role(RoleName='CloudCustodian-ExecutionRole')
            print("✅ Role found without path:")
            print(f"   ARN: {role['Role']['Arn']}")
            print(f"   Path: {role['Role']['Path']}")
            return role['Role']['Arn']
        except ClientError as e:
            if e.response['Error']['Code'] == 'NoSuchEntity':
                print("❌ Role not found without path")
            else:
                print(f"❌ Error checking role without path: {e}")
        
        # Check role with path
        try:
            role = iam.get_role(RoleName='CloudCustodian-ExecutionRole', RolePath='/cloud-custodian/')
            print("✅ Role found with path:")
            print(f"   ARN: {role['Role']['Arn']}")
            print(f"   Path: {role['Role']['Path']}")
            return role['Role']['Arn']
        except ClientError as e:
            if e.response['Error']['Code'] == 'NoSuchEntity':
                print("❌ Role not found with path")
            else:
                print(f"❌ Error checking role with path: {e}")
        
        return None
        
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return None

def main():
    print("🔍 Checking IAM Role ARN and Path")
    print("=" * 50)
    
    actual_arn = check_role_details()
    
    print("\n" + "=" * 50)
    print("📋 accounts.yml expects:")
    print("   ARN: arn:aws:iam::172327596604:role/CloudCustodian-ExecutionRole")
    
    if actual_arn:
        print(f"\n🔍 Actual ARN: {actual_arn}")
        if actual_arn == "arn:aws:iam::172327596604:role/CloudCustodian-ExecutionRole":
            print("✅ ARNs match - this is not the issue")
        else:
            print("❌ ARN mismatch - this is likely the issue!")
    else:
        print("\n❌ Could not determine actual ARN")

if __name__ == "__main__":
    main()