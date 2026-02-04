#!/bin/bash
# CBD Automation - Interactive Setup
# Run: bash cbd-automation/scripts/setup.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="$SCRIPT_DIR/../data"
CONFIG_FILE="$DATA_DIR/config.json"

mkdir -p "$DATA_DIR"

echo "🛠️  CBD Automation Setup"
echo "========================"
echo ""

# Check if already configured
if [ -f "$CONFIG_FILE" ]; then
    echo "⚠️  Config already exists at $CONFIG_FILE"
    read -p "Overwrite? (y/N): " overwrite
    if [ "$overwrite" != "y" ] && [ "$overwrite" != "Y" ]; then
        echo "Cancelled."
        exit 0
    fi
fi

echo ""
echo "📦 SHOPIFY CONFIGURATION"
echo "------------------------"
read -p "Store URL (e.g., your-store.myshopify.com): " shopify_store
read -p "Admin API Access Token: " shopify_token

echo ""
echo "📄 INV24 CONFIGURATION"
echo "----------------------"
read -p "INV24 Email: " inv24_email
read -sp "INV24 Password: " inv24_password
echo ""

echo ""
echo "🚚 ECONT CONFIGURATION"
echo "----------------------"
read -p "Econt Username: " econt_user
read -sp "Econt Password: " econt_password
echo ""
read -p "Sender Name: " econt_sender_name
read -p "Sender Phone: " econt_sender_phone
read -p "Sender City: " econt_sender_city
read -p "Sender Address: " econt_sender_address

echo ""
echo "📧 EMAIL CONFIGURATION"
echo "----------------------"
read -p "SMTP Host (e.g., smtp.gmail.com): " smtp_host
read -p "SMTP Port (e.g., 587): " smtp_port
read -p "Email Username: " email_user
read -sp "Email Password/App Password: " email_password
echo ""
read -p "From Name: " email_from_name
read -p "From Email: " email_from_address

echo ""
echo "🏢 BUSINESS INFO"
echo "----------------"
read -p "Company Name: " company_name
read -p "VAT Number (optional): " vat_number
read -p "Company City: " company_city
read -p "Company Address: " company_address

# Create config JSON
cat > "$CONFIG_FILE" << EOF
{
  "shopify": {
    "store": "$shopify_store",
    "accessToken": "$shopify_token"
  },
  "inv24": {
    "email": "$inv24_email",
    "password": "$inv24_password"
  },
  "econt": {
    "username": "$econt_user",
    "password": "$econt_password",
    "testMode": true,
    "sender": {
      "name": "$econt_sender_name",
      "phone": "$econt_sender_phone",
      "city": "$econt_sender_city",
      "address": "$econt_sender_address"
    }
  },
  "email": {
    "smtp": {
      "host": "$smtp_host",
      "port": $smtp_port
    },
    "username": "$email_user",
    "password": "$email_password",
    "from": {
      "name": "$email_from_name",
      "email": "$email_from_address"
    }
  },
  "business": {
    "name": "$company_name",
    "vat": "$vat_number",
    "city": "$company_city",
    "address": "$company_address"
  },
  "configuredAt": "$(date -Iseconds)"
}
EOF

chmod 600 "$CONFIG_FILE"

echo ""
echo "✅ Configuration saved to $CONFIG_FILE"
echo ""
echo "⚠️  Econt is in TEST MODE. Change 'testMode' to false for production."
echo ""
echo "Next steps:"
echo "  1. Test connections: bash scripts/test.sh --service shopify"
echo "  2. Set up Shopify webhook for new orders"
echo "  3. Say 'check orders' to start processing"
