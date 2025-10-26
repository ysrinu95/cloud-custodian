#!/usr/bin/env python3
"""
Debug script to check AssumeRole permissions for Cloud Custodian
"""

import boto3
import json
from botocore.exceptions import ClientError, NoCredentialsError

def check_current_identity():
    """Check current AWS identity"""
    try:
        sts = boto3.client('sts')
        identity = sts.get_caller_identity()
        print(f"✅ Current AWS Identity:")
        print(f"   Account: {identity['Account']}")
        print(f"   ARN: {identity['Arn']}")
        print(f"   User ID: {identity['UserId']}")
        return identity
    except NoCredentialsError:
        print("❌ No AWS credentials configured")
        return None
    except Exception as e:
        print(f"❌ Error getting caller identity: {e}")
        return None

def check_assume_role():
    """Test assuming the CloudCustodian-ExecutionRole"""
    role_arn = "arn:aws:iam::172327596604:role/CloudCustodian-ExecutionRole"
    
    try:
        sts = boto3.client('sts')
        response = sts.assume_role(
            RoleArn=role_arn,
            RoleSessionName='debug-test-session'
        )
        print(f"✅ Successfully assumed role: {role_arn}")
        return True
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        print(f"❌ AssumeRole failed:")
        print(f"   Error Code: {error_code}")
        print(f"   Error Message: {error_message}")
        
        if error_code == 'AccessDenied':
            print("\n🔍 Possible causes:")
            print("   1. The role's trust policy doesn't allow your identity to assume it")
            print("   2. Your current identity lacks sts:AssumeRole permission")
            print("   3. The role doesn't exist or ARN is incorrect")
        
        return False
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return False

def check_role_exists():
    """Check if the IAM role exists"""
    role_name = "CloudCustodian-ExecutionRole"
    
    try:
        iam = boto3.client('iam')
        role = iam.get_role(RoleName=role_name)
        print(f"✅ Role exists: {role_name}")
        
        # Check trust policy
        trust_policy = role['Role']['AssumeRolePolicyDocument']
        print(f"📋 Trust Policy:")
        print(json.dumps(trust_policy, indent=2))
        
        return True
    except ClientError as e:
        if e.response['Error']['Code'] == 'NoSuchEntity':
            print(f"❌ Role does not exist: {role_name}")
        else:
            print(f"❌ Error checking role: {e}")
        return False
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return False

def main():
    print("🔍 Cloud Custodian AssumeRole Debug Script")
    print("=" * 50)
    
    # Check current identity
    identity = check_current_identity()
    if not identity:
        return
    
    print("\n" + "=" * 50)
    
    # Check if role exists and get trust policy
    role_exists = check_role_exists()
    
    print("\n" + "=" * 50)
    
    # Test assume role
    assume_success = check_assume_role()
    
    print("\n" + "=" * 50)
    print("🏁 Summary:")
    
    if assume_success:
        print("✅ AssumeRole test passed - c7n-org should work")
    else:
        print("❌ AssumeRole test failed - this is why c7n-org fails")
        if role_exists:
            print("\n💡 Next steps:")
            print("   1. Check the trust policy shown above")
            print("   2. Ensure your current identity is allowed to assume the role")
            print("   3. Verify you have sts:AssumeRole permission")

if __name__ == "__main__":
    main()