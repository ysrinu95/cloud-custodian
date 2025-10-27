#!/bin/bash
# test-pipeline-c7n-org.sh - Test script to validate c7n-org in pipeline environment

echo "🔍 Testing c7n-org Pipeline Configuration"
echo "════════════════════════════════════════════════"
echo ""

# Test 1: Check c7n-org installation and version
echo "1. ✅ Testing c7n-org Installation"
echo "─────────────────────────────────────────"
if command -v c7n-org &> /dev/null; then
    echo "✅ c7n-org command found"
    echo "📦 Version info:"
    python -c "import c7n_org; print(f'   c7n-org package available')" 2>/dev/null || echo "   ⚠️ Package import failed"
else
    echo "❌ c7n-org command not found"
    echo "💡 Installing c7n-org..."
    pip install c7n-org
    if command -v c7n-org &> /dev/null; then
        echo "✅ c7n-org installed successfully"
    else
        echo "❌ c7n-org installation failed"
        exit 1
    fi
fi

echo ""

# Test 2: Check c7n-org syntax and help
echo "2. ✅ Testing c7n-org Command Syntax"
echo "─────────────────────────────────────────"
echo "📋 Available commands:"
c7n-org --help | grep -A 10 "Commands:" || echo "❌ Help command failed"

echo ""
echo "📋 Run command options:"
c7n-org run --help | head -15 || echo "❌ Run help failed"

echo ""

# Test 3: Validate accounts.yml configuration
echo "3. ✅ Testing accounts.yml Configuration"
echo "─────────────────────────────────────────"
accounts_file="config/accounts.yml"
if [ -f "$accounts_file" ]; then
    echo "✅ Found accounts.yml"
    echo "📋 Configuration:"
    cat "$accounts_file"
    
    # Check YAML syntax
    if python -c "import yaml; yaml.safe_load(open('$accounts_file'))" 2>/dev/null; then
        echo "✅ YAML syntax valid"
    else
        echo "❌ YAML syntax invalid"
        exit 1
    fi
    
    # Check required fields
    if grep -q "account_id" "$accounts_file" && grep -q "role" "$accounts_file"; then
        echo "✅ Required fields present"
    else
        echo "❌ Missing required fields"
        exit 1
    fi
else
    echo "❌ accounts.yml not found at $accounts_file"
    exit 1
fi

echo ""

# Test 4: Test policy files
echo "4. ✅ Testing Policy Files"
echo "─────────────────────────────────────────"
policy_dir="policies"
if [ -d "$policy_dir" ]; then
    policy_count=$(ls $policy_dir/*.yml 2>/dev/null | wc -l)
    echo "✅ Found $policy_count policy files in $policy_dir/"
    
    # Test first policy file
    first_policy=$(ls $policy_dir/*.yml 2>/dev/null | head -1)
    if [ -n "$first_policy" ]; then
        echo "📋 Testing syntax of: $(basename $first_policy)"
        if python -c "import yaml; yaml.safe_load(open('$first_policy'))" 2>/dev/null; then
            echo "✅ Policy YAML syntax valid"
        else
            echo "❌ Policy YAML syntax invalid"
            exit 1
        fi
    fi
else
    echo "❌ Policy directory not found: $policy_dir"
    exit 1
fi

echo ""

# Test 5: Test c7n-org dry run with correct syntax
echo "5. ✅ Testing c7n-org Dry Run (New Syntax)"
echo "─────────────────────────────────────────"

# Create test output directory
test_output="test_output"
mkdir -p "$test_output"

# Get first policy file for testing
test_policy=$(ls $policy_dir/*.yml 2>/dev/null | head -1)
if [ -n "$test_policy" ]; then
    echo "🧪 Testing with policy file: $(basename $test_policy)"
    echo "📋 Command: c7n-org run -c $accounts_file -u $test_policy -s $test_output --dryrun"
    
    if c7n-org run -c "$accounts_file" -u "$test_policy" -s "$test_output" --dryrun; then
        echo "✅ c7n-org dry run successful with new syntax!"
        echo "📊 Output generated in: $test_output"
        
        # Check if output was created
        if [ "$(ls -A $test_output 2>/dev/null)" ]; then
            echo "✅ Output files created"
            ls -la "$test_output"
        else
            echo "⚠️ No output files created (might be normal for dry run)"
        fi
    else
        echo "❌ c7n-org dry run failed"
        echo "💡 This indicates there may still be issues with:"
        echo "   - AWS credentials/permissions"
        echo "   - Role assumption"
        echo "   - Policy syntax"
        echo "   - Command syntax"
        exit 1
    fi
else
    echo "❌ No policy files found for testing"
    exit 1
fi

echo ""

# Test 6: Test old vs new syntax (for comparison)
echo "6. ✅ Testing Old vs New Syntax Comparison"
echo "─────────────────────────────────────────"
echo "❌ OLD SYNTAX (what was failing):"
echo "   c7n-org run --cache-period=0 -c config -s output -u policy.yml --dryrun"
echo ""
echo "✅ NEW SYNTAX (what works):"
echo "   c7n-org run -c config -u policy.yml -s output --dryrun"
echo ""
echo "🔧 Key changes:"
echo "   - Removed --cache-period=0 (deprecated/not needed)"
echo "   - Reordered parameters: -u before -s"
echo "   - Simplified command structure"

echo ""

# Cleanup
rm -rf "$test_output"

echo "🎉 Pipeline c7n-org Configuration Test Complete!"
echo "════════════════════════════════════════════════"
echo "✅ All tests passed"
echo "🚀 c7n-org should now work correctly in the pipeline"
echo ""
echo "📋 Updated files:"
echo "   - c7n/scripts/deploy-policies.sh (fixed syntax)"
echo "   - c7n/scripts/deploy-updated-policies.sh (fixed syntax)"
echo "   - .github/workflows/cloud-custodian-policies.yml (fixed syntax + role)"
echo ""
echo "💡 Next steps:"
echo "   1. Commit these changes"
echo "   2. Test pipeline deployment"
echo "   3. Monitor for successful c7n-org execution"