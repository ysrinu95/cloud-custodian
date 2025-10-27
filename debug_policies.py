#!/usr/bin/env python3
"""
Check IAM policies attached to CloudCustodian-ExecutionRole
"""

import boto3
import json
from botocore.exceptions import ClientError

def check_role_policies():
    """Check what policies are attached to the role"""
    role_name = 'CloudCustodian-ExecutionRole'
    
    try:
        iam = boto3.client('iam')
        
        print(f"🔍 Checking policies for role: {role_name}")
        print("=" * 50)
        
        # Get attached managed policies
        try:
            attached_policies = iam.list_attached_role_policies(RoleName=role_name)
            print(f"📋 Attached Managed Policies ({len(attached_policies['AttachedPolicies'])}):")
            
            if attached_policies['AttachedPolicies']:
                for policy in attached_policies['AttachedPolicies']:
                    print(f"   ✅ {policy['PolicyName']} - {policy['PolicyArn']}")
            else:
                print("   ❌ No managed policies attached!")
                
        except ClientError as e:
            print(f"❌ Error getting attached policies: {e}")
        
        # Get inline policies
        try:
            inline_policies = iam.list_role_policies(RoleName=role_name)
            print(f"\n📋 Inline Policies ({len(inline_policies['PolicyNames'])}):")
            
            if inline_policies['PolicyNames']:
                for policy_name in inline_policies['PolicyNames']:
                    print(f"   ✅ {policy_name}")
                    
                    # Get policy document
                    try:
                        policy_doc = iam.get_role_policy(RoleName=role_name, PolicyName=policy_name)
                        print(f"      📄 Policy Document:")
                        print(json.dumps(policy_doc['PolicyDocument'], indent=6))
                    except Exception as e:
                        print(f"      ❌ Error getting policy document: {e}")
            else:
                print("   ❌ No inline policies attached!")
                
        except ClientError as e:
            print(f"❌ Error getting inline policies: {e}")
            
        print("\n" + "=" * 50)
        print("💡 For Cloud Custodian, the role typically needs:")
        print("   ✅ AdministratorAccess (or comprehensive read/write permissions)")
        print("   ✅ CloudWatchLogsFullAccess (for Lambda logging)")
        print("   ✅ AWSLambdaBasicExecutionRole (for Lambda execution)")
        
    except Exception as e:
        print(f"❌ Unexpected error: {e}")

if __name__ == "__main__":
    check_role_policies()