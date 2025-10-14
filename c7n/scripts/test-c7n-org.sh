#!/bin/bash
# test-c7n-org.sh - Test script to verify c7n-org command syntax

echo "Testing c7n-org command availability and syntax..."

# Test 1: Check if c7n-org is available
echo "1. Checking if c7n-org is available..."
if command -v c7n-org &> /dev/null; then
    echo "✅ c7n-org command found"
else
    echo "❌ c7n-org command not found"
    echo "   Please install: pip install c7n[org]"
    exit 1
fi

# Test 2: Check help output
echo ""
echo "2. Testing c7n-org help..."
c7n-org --help > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✅ c7n-org help works"
else
    echo "❌ c7n-org help failed"
    exit 1
fi

# Test 3: Show available commands
echo ""
echo "3. Available c7n-org commands:"
c7n-org --help | grep -A 10 "Commands:"

# Test 4: Check run command help
echo ""
echo "4. Testing c7n-org run command help..."
c7n-org run --help > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✅ c7n-org run command available"
else
    echo "❌ c7n-org run command failed"
    exit 1
fi

echo ""
echo "✅ All c7n-org tests passed!"
echo ""
echo "Example usage:"
echo "c7n-org run -c config/accounts.yml -s output/ -u policies/"