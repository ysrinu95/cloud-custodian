#!/bin/bash
# Deploys c7n policies

config=config/accounts.yml
output_dir=s3://ysr95-cloud-custodian-logs-26zsuuw4
policy_dir=policies
dryrun=
account=

while getopts 'lda:' OPTION; do
  case "$OPTION" in
    l)
      echo "local run..."
      output_dir=.c7n 
      ;;
    d)
      echo "running deploy as dry run..."
      dryrun=--dryrun 
      ;;
    a)
      echo "running deploy for account [$OPTARG]..."
      account="-a $OPTARG"
      ;;
    ?)
      echo "script usage: $(basename \$0) [-l] [-d] [-a <account>]" >&2
      exit 1
      ;;
  esac
done

for FILE in $policy_dir/*.yml; do
  echo "running policy file: $FILE"
  c7n-org run -c $config -u $FILE -s $output_dir $account $dryrun
done

# local
#   set 'profile' in accounts.yml
#   > c7n-org run --cache-period=0 -c config/accounts.yml -s .c7n -a development -r us-west-2 -u policies/baseline.yml -p policy-name --dryrun