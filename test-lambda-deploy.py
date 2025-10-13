#!/usr/bin/env python3
"""
Test script for Cloud Custodian Lambda deployment
This script helps validate policy files and test Lambda deployment approaches
"""

import os
import subprocess
import sys
import json
from pathlib import Path

def get_custodian_path():
    """Get the path to custodian executable"""
    import site
    
    # Check user installation first
    user_scripts = os.path.join(site.USER_BASE, 'Python311', 'Scripts')
    custodian_exe = os.path.join(user_scripts, 'custodian.exe')
    if os.path.exists(custodian_exe):
        return custodian_exe
    
    # Try alternate user path
    alt_user_scripts = os.path.join(site.USER_BASE, 'Scripts')
    alt_custodian_exe = os.path.join(alt_user_scripts, 'custodian.exe')
    if os.path.exists(alt_custodian_exe):
        return alt_custodian_exe
    
    # Try system installation
    system_custodian = os.path.join(sys.prefix, 'Scripts', 'custodian.exe')
    if os.path.exists(system_custodian):
        return system_custodian
    
    # Fallback to just 'custodian' (might be in PATH)
    return 'custodian'

def run_command(cmd, check=True):
    """Run a command and return the result"""
    # Replace 'custodian' with full path if it's the first argument
    if cmd[0] == 'custodian':
        cmd[0] = get_custodian_path()
    
    print(f"🔄 Running: {' '.join(cmd)}")
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=check)
        if result.stdout:
            print(f"✅ Output: {result.stdout.strip()}")
        return result
    except subprocess.CalledProcessError as e:
        print(f"❌ Error: {e}")
        if e.stdout:
            print(f"Stdout: {e.stdout}")
        if e.stderr:
            print(f"Stderr: {e.stderr}")
        if check:
            raise
        return e
    except FileNotFoundError as e:
        print(f"❌ Command not found: {e}")
        if check:
            raise
        return type('MockResult', (), {'returncode': 1, 'stdout': '', 'stderr': str(e)})()

def check_custodian_installation():
    """Check if Cloud Custodian is properly installed"""
    print("🔍 Checking Cloud Custodian installation...")
    
    try:
        # Try importing c7n
        import c7n
        print(f"✅ c7n module found: {c7n.__file__}")
        
        # Check custodian command
        result = run_command(['custodian', 'version'], check=False)
        if result.returncode == 0:
            print("✅ custodian command available")
            return True
        else:
            print("❌ custodian command not available")
            return False
            
    except ImportError as e:
        print(f"❌ c7n module not found: {e}")
        return False

def validate_policies():
    """Validate all policy files"""
    print("\n🔍 Validating policy files...")
    
    policies_dir = Path("policies")
    if not policies_dir.exists():
        print("❌ Policies directory not found")
        return False
    
    policy_files = list(policies_dir.glob("*.yml")) + list(policies_dir.glob("*.yaml"))
    if not policy_files:
        print("❌ No policy files found")
        return False
    
    all_valid = True
    for policy_file in policy_files:
        print(f"\n📋 Validating: {policy_file}")
        result = run_command(['custodian', 'validate', str(policy_file)], check=False)
        if result.returncode != 0:
            print(f"❌ Validation failed for {policy_file}")
            all_valid = False
        else:
            print(f"✅ Valid: {policy_file}")
    
    return all_valid

def analyze_policies():
    """Analyze policy files for Lambda deployment readiness"""
    print("\n🔍 Analyzing policies for Lambda deployment...")
    
    policies_dir = Path("policies")
    policy_files = list(policies_dir.glob("*.yml")) + list(policies_dir.glob("*.yaml"))
    
    lambda_ready = []
    standard_policies = []
    
    for policy_file in policy_files:
        with open(policy_file, 'r') as f:
            content = f.read()
            
        if 'mode:' in content:
            if 'type: periodic' in content or 'type: cloudtrail' in content:
                lambda_ready.append(policy_file)
            else:
                standard_policies.append(policy_file)
        else:
            standard_policies.append(policy_file)
    
    print(f"\n📊 Policy Analysis:")
    print(f"  🚀 Lambda-ready policies: {len(lambda_ready)}")
    for policy in lambda_ready:
        print(f"    - {policy.name}")
    
    print(f"  📋 Standard policies: {len(standard_policies)}")
    for policy in standard_policies:
        print(f"    - {policy.name}")
    
    return lambda_ready, standard_policies

def test_dry_run():
    """Test dry run of policies"""
    print("\n🧪 Testing policy dry runs...")
    
    policies_dir = Path("policies")
    policy_files = list(policies_dir.glob("*.yml")) + list(policies_dir.glob("*.yaml"))
    
    output_dir = Path("test-output")
    output_dir.mkdir(exist_ok=True)
    
    for policy_file in policy_files:
        print(f"\n🔄 Testing dry run: {policy_file}")
        result = run_command([
            'custodian', 'run',
            '--dryrun',
            '-s', str(output_dir / policy_file.stem),
            str(policy_file)
        ], check=False)
        
        if result.returncode == 0:
            print(f"✅ Dry run successful: {policy_file}")
        else:
            print(f"❌ Dry run failed: {policy_file}")

def main():
    """Main test function"""
    print("🚀 Cloud Custodian Lambda Deployment Test")
    print("=" * 50)
    
    # Check if we're in the right directory
    if not Path("policies").exists():
        print("❌ Please run this script from the cloud-custodian project root")
        sys.exit(1)
    
    # Test 1: Check installation
    if not check_custodian_installation():
        print("\n💡 To install Cloud Custodian:")
        print("   pip install 'c7n>=0.9.40'")
        sys.exit(1)
    
    # Test 2: Validate policies
    if not validate_policies():
        print("\n❌ Policy validation failed")
        sys.exit(1)
    
    # Test 3: Analyze policies
    lambda_ready, standard_policies = analyze_policies()
    
    # Test 4: Test dry runs
    test_dry_run()
    
    print("\n🎉 All tests completed!")
    print("\n📋 Summary:")
    print(f"  ✅ Policies validated: {len(lambda_ready + standard_policies)}")
    print(f"  🚀 Lambda-ready policies: {len(lambda_ready)}")
    print(f"  📋 Standard policies: {len(standard_policies)}")
    
    print("\n💡 Next steps:")
    print("  1. Run the GitHub Actions 'Deploy Cloud Custodian Lambda Functions' workflow")
    print("  2. Monitor the deployment in AWS Lambda console")
    print("  3. Check CloudWatch Events for policy triggers")

if __name__ == "__main__":
    main()