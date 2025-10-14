#!/bin/bash
# Runs enhanced garbage collection to clean up resources belonging
#  to policies that have been removed.
# This enhanced version properly handles CloudWatch Events rules with targets.

config=config/accounts.yml
output_dir=.c7n/gc # run-script only supports local output
policy_dir=policies
dryrun=
present=
region=
account=
verbose=

while getopts 'dpvr:a:' OPTION; do
  case "$OPTION" in
    d)
      echo "🔍 Running garbage collection as dry run..."
      dryrun=--dryrun 
      ;;
    p)
      echo "🎯 Running garbage collection against present policies..."
      present=--present 
      ;;
    v)
      echo "📝 Enabling verbose output..."
      verbose=-v
      ;;
    r)
      echo "🌍 Running garbage collection on region [$OPTARG]..."
      region="-r $OPTARG"
      ;;
    a)
      echo "🏢 Running garbage collection for account [$OPTARG]..."
      account="-a $OPTARG"
      ;;
    ?)
      echo "script usage: $(basename \$0) [-d] [-p] [-v] [-r <region>] [-a <account>]" >&2
      echo ""
      echo "Options:"
      echo "  -d          Dry run mode (show what would be deleted)"
      echo "  -p          Target policies present in config files for removal"
      echo "  -v          Verbose output"
      echo "  -r <region> Target specific AWS region"
      echo "  -a <account> Target specific account"
      exit 1
      ;;
  esac
done

echo "📁 Constructing list of policy files..."
FILES=
for FILE in $policy_dir/*.yml; do
  if [ -f "$FILE" ]; then
    FILES+="$FILE "
  fi
done

if [ -z "$FILES" ]; then
  echo "❌ No policy files found in $policy_dir"
  exit 1
fi

echo "🧹 Running enhanced cleanup on policy files: $FILES"

# Check if enhanced garbage collection script exists
if [ -f "scripts/mugc-enhanced.py" ]; then
  echo "✨ Using enhanced garbage collection script (handles CloudWatch Events properly)"
  cleanup_script="$(pwd)/scripts/mugc-enhanced.py"
else
  echo "⚠️  Using standard garbage collection script"
  cleanup_script="$(pwd)/scripts/mugc.py"
fi

# Build the command
cleanup_cmd="$(which python3) $cleanup_script -c $FILES $present $dryrun $verbose"

if [ -n "$account" ]; then
  # Run for specific account
  echo "🎯 Running cleanup for specific account..."
  c7n-org run-script $region -s $output_dir -c $config $account "$cleanup_cmd"
else
  # Run for all accounts
  echo "🌐 Running cleanup for all accounts..."
  c7n-org run-script $region -s $output_dir -c $config "$cleanup_cmd"
fi

echo "✅ Cleanup process completed"

# local
#   > python scripts/mugc.py -c list-of-files --profile shared-a --dryrun