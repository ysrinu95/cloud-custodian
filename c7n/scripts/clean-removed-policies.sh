#!/bin/bash
# Runs garbage collection to clean up resources belonging
#  to policies that have been removed.

config=config/accounts.yml
output_dir=.c7n/gc # run-script only supports local output
policy_dir=policies
dryrun=
present=
region=

while getopts 'dpr:' OPTION; do
  case "$OPTION" in
    d)
      echo "running garbage collection as dry run..."
      dryrun=--dryrun 
      ;;
    p)
      echo "running garbage collection against present policies..."
      present=--present 
      ;;
    r)
      echo "running garbage collection on region [$OPTARG]..."
      region="-r $OPTARG"
      ;;
    ?)
      echo "script usage: $(basename \$0) [-d] [-p] [-r <region>]" >&2
      exit 1
      ;;
  esac
done

echo "constructing list of policy files..."
FILES=
for FILE in $policy_dir/*.yml; do
  FILES+="$FILE "
done

echo "running cleanup on policy files: $FILES"
c7n-org run-script $region -s $output_dir -c $config "$(which python3) $(pwd)/scripts/mugc.py -c $FILES $present $dryrun"

# local
#   > python scripts/mugc.py -c list-of-files --profile shared-a --dryrun