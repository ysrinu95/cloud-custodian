#!/bin/bash
# Deploys c7n policies that have been updated

config=config/accounts.yml
output_dir=s3://gs-s3-cloud-custodian-logs
policy_dir=policies
dryrun=
account=
commit_diff="--source HEAD~1 --target HEAD" # for main branch

while getopts 'tda:' OPTION; do
  case "$OPTION" in
    t)
      # for topic branches and local runs
      echo "topic branch run..."
      commit_diff="--source origin/main --target HEAD"
      ;;
    d)
      # for all validation runs and local testing
      echo "running deploy as dry run..."
      output_dir=.c7n
      dryrun=--dryrun 
      ;;
    a)
      echo "running targeted deploy for account [$OPTARG]..."
      account="-a $OPTARG"
      ;;
    ?)
      echo "script usage: $(basename \$0) [-t] [-d] [-a <account>]" >&2
      exit 1
      ;;
  esac
done

echo "fetching origin git ref..."
git fetch origin "+refs/heads/main:refs/remotes/origin/main"

changed_policies=$(c7n-policystream diff $commit_diff | yq -r .policies[].name)
echo -e "\nchanged policies that require deployment:" 
printf '%s\n' "${changed_policies[@]}"

# iterate policy files since c7n-org doesn't currently have a way to take in a directory
for FILE in $policy_dir/*.yml; do
  echo -e "\nchecking policy file: $FILE"
  
  # iterate policies that have changed
  for policy in $changed_policies; do
    # check if the changed policy exists in the current policy file
    #  policy names are unique and will only exist once
    if grep -Fq $policy $FILE; then
      echo "$policy exists in this policy file, deploying..."
      c7n-org run -c $config -u $FILE -s $output_dir $account -p $policy $dryrun
    fi
  done
done


# local
#   set 'profile' in accounts.yml
#   > c7n-org run --cache-period=0 -c config/accounts.yml -s .c7n -a development -r us-west-2 -u policies/baseline.yml -p policy-name --dryrun