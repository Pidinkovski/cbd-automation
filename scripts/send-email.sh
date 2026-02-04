#!/bin/bash
# Send customer email with order confirmation
# Usage: bash send-email.sh --order-id ORDER_ID

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="$SCRIPT_DIR/../data"
CONFIG_FILE="$DATA_DIR/config.json"
ORDERS_FILE="$DATA_DIR/orders.json"
AUDIT_LOG="$DATA_DIR/audit.log"
TEMPLATE_DIR="$SCRIPT_DIR/../templates"

if [ ! -f "$CONFIG_FILE" ] || [ ! -f "$ORDERS_FILE" ]; then
    echo "❌ Config or orders file not found."
    exit 1
fi

# Parse arguments
ORDER_ID=""
PREVIEW=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --order-id) ORDER_ID="$2"; shift 2 ;;
        --preview) PREVIEW="true"; shift ;;
        *) shift ;;
    esac
done

if [ -z "$ORDER_ID" ]; then
    echo "❌ --order-id is required"
    exit 1
fi

# Normalize order ID
if [[ ! "$ORDER_ID" == order_* ]]; then
    ORDER_ID="order_$ORDER_ID"
fi

# Get order
ORDER=$(jq -r ".\"$ORDER_ID\"" "$ORDERS_FILE")
if [ "$ORDER" == "null" ]; then
    echo "❌ Order '$ORDER_ID' not found."
    exit 1
fi

# Check if already sent
EMAIL_SENT=$(echo "$ORDER" | jq -r '.email.sent')
if [ "$EMAIL_SENT" == "true" ]; then
    echo "⚠️ Email already sent for this order."
    exit 0
fi

# Extract data
ORDER_NUM=$(echo "$ORDER" | jq -r '.orderNumber')
CUSTOMER_NAME=$(echo "$ORDER" | jq -r '.customer.name')
CUSTOMER_EMAIL=$(echo "$ORDER" | jq -r '.customer.email')
TRACKING=$(echo "$ORDER" | jq -r '.shipment.tracking // "N/A"')
INVOICE_ID=$(echo "$ORDER" | jq -r '.invoice.id // "N/A"')
TOTAL=$(echo "$ORDER" | jq -r '.total')
PAYMENT=$(echo "$ORDER" | jq -r '.payment')

# Check if we have email
if [ -z "$CUSTOMER_EMAIL" ] || [ "$CUSTOMER_EMAIL" == "null" ] || [ "$CUSTOMER_EMAIL" == "" ]; then
    echo "⚠️ No email address for this order (probably a phone order)."
    echo ""
    echo "Mark as completed without email?"
    echo "Use: bash update-order.sh --order-id $ORDER_ID --email-sent"
    exit 0
fi

# Get email config
SMTP_HOST=$(jq -r '.email.smtp.host' "$CONFIG_FILE")
SMTP_PORT=$(jq -r '.email.smtp.port' "$CONFIG_FILE")
EMAIL_USER=$(jq -r '.email.username' "$CONFIG_FILE")
EMAIL_PASS=$(jq -r '.email.password' "$CONFIG_FILE")
FROM_NAME=$(jq -r '.email.from.name' "$CONFIG_FILE")
FROM_EMAIL=$(jq -r '.email.from.email' "$CONFIG_FILE")
COMPANY_NAME=$(jq -r '.business.name' "$CONFIG_FILE")

# Build items list
ITEMS_TEXT=$(echo "$ORDER" | jq -r '.items[] | "• \(.qty)x \(.name) - \(.price) BGN"')

# Build email content
SUBJECT="Поръчка #$ORDER_NUM е изпратена!"

BODY="Здравейте, $CUSTOMER_NAME!

Благодарим Ви за поръчката!

Вашата пратка вече е на път към Вас.

📦 Номер на пратка: $TRACKING
🔗 Проследяване: https://www.econt.com/services/track-shipment?shipmentNumber=$TRACKING

Детайли на поръчката:
$ITEMS_TEXT

Обща сума: $TOTAL BGN"

if [ "$PAYMENT" == "cod" ]; then
    BODY="$BODY

💵 Дължима сума при доставка: $TOTAL BGN"
fi

BODY="$BODY

При въпроси, моля свържете се с нас.

Поздрави,
$COMPANY_NAME"

# Preview mode
if [ "$PREVIEW" == "true" ]; then
    echo "📧 **Email Preview**"
    echo ""
    echo "To: $CUSTOMER_EMAIL"
    echo "From: $FROM_NAME <$FROM_EMAIL>"
    echo "Subject: $SUBJECT"
    echo ""
    echo "---"
    echo "$BODY"
    echo "---"
    exit 0
fi

echo "📧 Sending email to $CUSTOMER_EMAIL..."

# Send email using curl and SMTP
# This uses curl's SMTP capabilities

# Create email file
EMAIL_FILE=$(mktemp)
cat > "$EMAIL_FILE" << EOF
From: $FROM_NAME <$FROM_EMAIL>
To: $CUSTOMER_EMAIL
Subject: =?UTF-8?B?$(echo -n "$SUBJECT" | base64)?=
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 8bit

$BODY
EOF

# Send via curl
RESULT=$(curl -s --url "smtp://$SMTP_HOST:$SMTP_PORT" \
    --ssl-reqd \
    --mail-from "$FROM_EMAIL" \
    --mail-rcpt "$CUSTOMER_EMAIL" \
    --user "$EMAIL_USER:$EMAIL_PASS" \
    --upload-file "$EMAIL_FILE" \
    -w "%{http_code}" \
    -o /dev/null 2>&1)

rm -f "$EMAIL_FILE"

# Check result - curl returns empty on SMTP success
if [ -z "$RESULT" ] || [ "$RESULT" == "0" ] || [ "$RESULT" == "250" ]; then
    # Update order
    jq ".\"$ORDER_ID\".email.sent = true | .\"$ORDER_ID\".status = \"completed\"" \
        "$ORDERS_FILE" > "$ORDERS_FILE.tmp" && mv "$ORDERS_FILE.tmp" "$ORDERS_FILE"
    
    # Audit log
    echo "$(date -Iseconds) | EMAIL_SENT | $ORDER_ID | To: $CUSTOMER_EMAIL" >> "$AUDIT_LOG"
    
    echo "✅ Email sent to $CUSTOMER_EMAIL"
else
    echo "$(date -Iseconds) | EMAIL_FAILED | $ORDER_ID | Error sending to $CUSTOMER_EMAIL" >> "$AUDIT_LOG"
    echo "❌ Failed to send email"
    echo "Error: $RESULT"
    echo ""
    echo "You can try again or mark as sent manually:"
    echo "  bash update-order.sh --order-id $ORDER_ID --email-sent"
    exit 1
fi
