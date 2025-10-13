#!/bin/bash
# Deploys c7n-mailer

config=config/mailer.yml
templates_dir=config/mailer-templates

c7n-mailer --config $config -t $templates_dir --update-lambda

# local
#   > AWS_PROFILE=shared-a c7n-mailer --config config/mailer.yml -t config/mailer-templates  --update-lambda