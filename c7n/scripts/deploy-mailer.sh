#!/bin/bash
# Deploys c7n-mailer with all required dependencies

config=config/mailer.yml
templates_dir=config/mailer-templates

echo "🔧 Setting up clean environment for mailer deployment..."

# Install all dependencies including PyJWT in current environment
echo "📦 Installing all mailer dependencies..."
pip install --upgrade pip setuptools wheel

# Use exact versions to avoid conflicts
echo "📦 Installing specific dependency versions to avoid conflicts..."
pip install --force-reinstall PyJWT==2.8.0
pip install --force-reinstall cryptography==44.0.0  
pip install --force-reinstall requests==2.32.4
pip install --force-reinstall decorator>=4.4.0
pip install --force-reinstall c7n>=0.9.21
pip install --force-reinstall c7n-mailer>=0.6.20

echo "📦 Verifying critical dependencies..."
python -c "import jwt; print(f'✅ PyJWT version: {jwt.__version__}')" || echo "❌ PyJWT not available"
python -c "import cryptography; print('✅ cryptography available')" || echo "❌ cryptography not available"
python -c "import c7n_mailer; print('✅ c7n-mailer available')" || echo "❌ c7n-mailer not available"

# Create a requirements file for the Lambda
echo "� Creating Lambda requirements file..."
cat > lambda-requirements.txt << EOF
PyJWT==2.8.0
cryptography==44.0.0
requests==2.32.4
decorator>=4.4.0
EOF

# Install requirements in site-packages to ensure they're picked up by c7n-mailer
echo "📦 Installing requirements globally for Lambda packaging..."
pip install -r lambda-requirements.txt

echo "�📧 Deploying c7n-mailer with --update-lambda..."
c7n-mailer --config $config -t $templates_dir --update-lambda

# Clean up temporary requirements file
rm -f lambda-requirements.txt

echo "✅ Mailer deployment complete"

# local
#   > AWS_PROFILE=shared-a c7n-mailer --config config/mailer.yml -t config/mailer-templates  --update-lambda