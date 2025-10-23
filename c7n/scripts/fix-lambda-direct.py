#!/usr/bin/env python3
"""
Direct Lambda function updater for c7n-mailer with PyJWT
This script manually packages the Lambda function with required dependencies
"""

import subprocess
import tempfile
import zipfile
import json
import os
import shutil
from pathlib import Path

def run_command(cmd, cwd=None):
    """Run a command and return the result"""
    print(f"Running: {cmd}")
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=cwd)
    if result.returncode != 0:
        print(f"Error: {result.stderr}")
        return False, result.stderr
    return True, result.stdout

def main():
    lambda_function_name = "cloud-custodian-mailer"
    region = "us-west-2"
    
    print("🔧 Direct Lambda PyJWT Fix")
    print("=" * 50)
    
    # Create temporary directory
    with tempfile.TemporaryDirectory() as temp_dir:
        print(f"📁 Working in: {temp_dir}")
        
        # Download current Lambda function
        print("⬇️ Downloading Lambda function...")
        success, output = run_command(f'aws lambda get-function --function-name {lambda_function_name} --region {region} --query "Code.Location" --output text')
        if not success:
            print("❌ Failed to get Lambda function")
            return
        
        download_url = output.strip()
        zip_path = os.path.join(temp_dir, "function.zip")
        
        # Download the zip file
        success, _ = run_command(f'curl -s -o "{zip_path}" "{download_url}"')
        if not success:
            print("❌ Failed to download function")
            return
        
        # Extract the function
        print("📦 Extracting Lambda function...")
        extract_dir = os.path.join(temp_dir, "function")
        os.makedirs(extract_dir, exist_ok=True)
        
        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            zip_ref.extractall(extract_dir)
        
        # Install PyJWT and dependencies directly into the function directory
        print("📦 Installing PyJWT and dependencies...")
        deps_to_install = [
            "PyJWT==2.8.0",
            "cryptography==44.0.0", 
            "requests==2.32.4",
            "decorator>=4.4.0"
        ]
        
        for dep in deps_to_install:
            print(f"   Installing {dep}...")
            success, _ = run_command(f'pip install --target "{extract_dir}" --no-deps {dep}')
            if not success:
                print(f"⚠️ Warning: Failed to install {dep}")
        
        # Create new zip file
        print("📦 Creating updated Lambda package...")
        new_zip_path = os.path.join(temp_dir, "function-updated.zip")
        
        with zipfile.ZipFile(new_zip_path, 'w', zipfile.ZIP_DEFLATED) as zip_ref:
            for root, dirs, files in os.walk(extract_dir):
                for file in files:
                    file_path = os.path.join(root, file)
                    arcname = os.path.relpath(file_path, extract_dir)
                    zip_ref.write(file_path, arcname)
        
        # Update Lambda function
        print("⬆️ Updating Lambda function...")
        success, output = run_command(f'aws lambda update-function-code --function-name {lambda_function_name} --region {region} --zip-file fileb://"{new_zip_path}"')
        if success:
            print("✅ Lambda function updated successfully!")
            
            # Test the function
            print("🧪 Testing Lambda function...")
            response_file = os.path.join(temp_dir, "test_response.json")
            success, _ = run_command(f'aws lambda invoke --function-name {lambda_function_name} --region {region} --payload "{{}}" "{response_file}"')
            
            if success and os.path.exists(response_file):
                with open(response_file, 'r') as f:
                    response = json.load(f)
                print(f"📋 Test Response: {json.dumps(response, indent=2)}")
            
        else:
            print("❌ Failed to update Lambda function")
            print(output)

if __name__ == "__main__":
    main()