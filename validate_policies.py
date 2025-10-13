#!/usr/bin/env python3
"""
Cloud Custodian Policy Validation Script
"""
import sys
import os
from c7n.commands import main

def validate_policy(policy_file):
    """Validate a single policy file"""
    try:
        # Use c7n's main function with validate command
        sys.argv = ['custodian', 'validate', policy_file]
        main()
        return True
    except SystemExit as e:
        return e.code == 0
    except Exception as e:
        print(f"Error validating {policy_file}: {e}")
        return False

def main_validation():
    """Main validation function"""
    print("=== Cloud Custodian Policy Validation ===")
    
    # Find all policy files
    policy_files = []
    policies_dir = "policies"
    
    if os.path.exists(policies_dir):
        for file in os.listdir(policies_dir):
            if file.endswith('.yml') or file.endswith('.yaml'):
                policy_files.append(os.path.join(policies_dir, file))
    
    if not policy_files:
        print("No policy files found in policies/ directory")
        return False
    
    print(f"Found {len(policy_files)} policy file(s) to validate:")
    for file in policy_files:
        print(f"  - {file}")
    
    print("\n=== Validation Results ===")
    
    all_valid = True
    for policy_file in policy_files:
        print(f"\nValidating {policy_file}...")
        if validate_policy(policy_file):
            print(f"✓ {policy_file} is VALID")
        else:
            print(f"✗ {policy_file} has ERRORS")
            all_valid = False
    
    print(f"\n=== Summary ===")
    if all_valid:
        print("✓ All policies are valid!")
        return True
    else:
        print("✗ Some policies have validation errors")
        return False

if __name__ == "__main__":
    success = main_validation()
    sys.exit(0 if success else 1)