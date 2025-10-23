#!/bin/bash
# Deploys c7n-mailer with all required dependencies

config=config/mailer.yml
templates_dir=config/mailer-templates

echo "🔧 Installing mailer runtime dependencies..."
pip install PyJWT>=2.0.0 cryptography>=3.0.0 requests>=2.25.0

echo "📧 Deploying c7n-mailer..."
c7n-mailer --config $config -t $templates_dir --update-lambda

echo "✅ Mailer deployment complete"

# local
#   > AWS_PROFILE=shared-a c7n-mailer --config config/mailer.yml -t config/mailer-templates  --update-lambda