#!/bin/bash
# Deploys c7n-mailer with all required dependencies

config=config/mailer.yml
templates_dir=config/mailer-templates

echo "🔧 Setting up clean environment for mailer deployment..."

# Install all dependencies including PyJWT in current environment
echo "📦 Installing all mailer dependencies..."
pip install --upgrade pip setuptools wheel
pip install --force-reinstall PyJWT>=2.0.0
pip install --force-reinstall cryptography>=3.0.0  
pip install --force-reinstall requests>=2.25.0
pip install --force-reinstall decorator>=4.4.0
pip install --force-reinstall c7n>=0.9.21
pip install --force-reinstall c7n-mailer>=0.6.20

echo "📦 Verifying critical dependencies..."
python -c "import jwt; print(f'✅ PyJWT version: {jwt.__version__}')" || echo "❌ PyJWT not available"
python -c "import cryptography; print('✅ cryptography available')" || echo "❌ cryptography not available"
python -c "import c7n_mailer; print('✅ c7n-mailer available')" || echo "❌ c7n-mailer not available"

echo "📧 Deploying c7n-mailer with --update-lambda..."
c7n-mailer --config $config -t $templates_dir --update-lambda

echo "✅ Mailer deployment complete"

# local
#   > AWS_PROFILE=shared-a c7n-mailer --config config/mailer.yml -t config/mailer-templates  --update-lambda