#!/usr/bin/env python3
"""
Cloud Custodian Policy Validation Script
"""
import sys
import os
import argparse
from c7n.commands import validate

def main():
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
        
        # Create minimal config for validation
        options = argparse.Namespace()
        options.configs = [policy_file]
        options.verbose = False
        options.debug = False
        options.check_deprecations = False
        options.strict = False
        
        try:
            result = validate(options)
            if result:
                print(f"✗ {policy_file} has ERRORS")
                all_valid = False
            else:
                print(f"✓ {policy_file} is VALID")
        except Exception as e:
            print(f"✗ {policy_file} failed validation: {e}")
            all_valid = False
    
    print(f"\n=== Summary ===")
    if all_valid:
        print("✓ All policies are valid!")
        return True
    else:
        print("✗ Some policies have validation errors")
        return False

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)