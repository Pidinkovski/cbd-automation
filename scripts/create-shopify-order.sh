#!/bin/bash
# Create order in Shopify (for manual/phone orders)
# Usage: bash create-shopify-order.sh --name "Name" --phone "Phone" --city "City" --address "Addr" --postal "1000" --items '[...]' --payment "cod"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="$SCRIPT_DIR/../data"
CONFIG_FILE="$DATA_DIR/config.json"
ORDERS_FILE="$DATA_DIR/orders.json"
AUDIT_LOG="$DATA_DIR/audit.log"

mkdir -p "$DATA_DIR"

# Check config exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Config not found. Run setup.sh first."
    exit 1
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --name) NAME="$2"; shift 2 ;;
        --phone) PHONE="$2"; shift 2 ;;
        --email) EMAIL="$2"; shift 2 ;;
        --city) CITY="$2"; shift 2 ;;
        --address) ADDRESS="$2"; shift 2 ;;
        --postal) POSTAL="$2"; shift 2 ;;
        --items) ITEMS="$2"; shift 2 ;;
        --payment) PAYMENT="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Validate required fields
if [ -z "$NAME" ] || [ -z "$PHONE" ] || [ -z "$CITY" ] || [ -z "$ADDRESS" ] || [ -z "$ITEMS" ]; then
    echo "❌ Missing required fields"
    echo "Usage: create-shopify-order.sh --name \"Name\" --phone \"Phone\" --city \"City\" --address \"Addr\" --postal \"1000\" --items '[{\"name\":\"Product\",\"qty\":1,\"price\":45,\"variant_id\":12345}]'"
    exit 1
fi

# Defaults
PAYMENT="${PAYMENT:-cod}"
EMAIL="${EMAIL:-}"
POSTAL="${POSTAL:-}"

# Get Shopify config
STORE=$(jq -r '.shopify.store' "$CONFIG_FILE")
TOKEN=$(jq -r '.shopify.accessToken' "$CONFIG_FILE")

if [ -z "$STORE" ] || [ "$STORE" == "null" ]; then
    echo "❌ Shopify store not configured"
    exit 1
fi

# Calculate total
TOTAL=$(echo "$ITEMS" | jq '[.[] | .qty * .price] | add')

# Split name into first/last
FIRST_NAME=$(echo "$NAME" | awk '{print $1}')
LAST_NAME=$(echo "$NAME" | awk '{$1=""; print $0}' | xargs)
[ -z "$LAST_NAME" ] && LAST_NAME="."

# Build line items for Shopify
# Note: If variant_id is not provided, we create custom line items
LINE_ITEMS=$(echo "$ITEMS" | jq '[.[] | {
    title: .name,
    quantity: .qty,
    price: (.price | tostring),
    requires_shipping: true
}]')

# Determine financial status
if [ "$PAYMENT" == "prepaid" ] || [ "$PAYMENT" == "paid" ]; then
    FINANCIAL_STATUS="paid"
else
    FINANCIAL_STATUS="pending"
fi

# Build order JSON
ORDER_JSON=$(cat << EOF
{
  "order": {
    "line_items": $LINE_ITEMS,
    "customer": {
      "first_name": "$FIRST_NAME",
      "last_name": "$LAST_NAME",
      "email": "$EMAIL",
      "phone": "$PHONE"
    },
    "billing_address": {
      "first_name": "$FIRST_NAME",
      "last_name": "$LAST_NAME",
      "address1": "$ADDRESS",
      "city": "$CITY",
      "zip": "$POSTAL",
      "country": "Bulgaria",
      "phone": "$PHONE"
    },
    "shipping_address": {
      "first_name": "$FIRST_NAME",
      "last_name": "$LAST_NAME",
      "address1": "$ADDRESS",
      "city": "$CITY",
      "zip": "$POSTAL",
      "country": "Bulgaria",
      "phone": "$PHONE"
    },
    "financial_status": "$FINANCIAL_STATUS",
    "note": "Manual order created via bot",
    "tags": "manual-order, bot-created",
    "send_receipt": false,
    "send_fulfillment_receipt": false
  }
}
EOF
)

echo "🔄 Creating order in Shopify..."

# Make API request
RESPONSE=$(curl -s -X POST \
    "https://$STORE/admin/api/2024-01/orders.json" \
    -H "X-Shopify-Access-Token: $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$ORDER_JSON")

# Check for errors
if echo "$RESPONSE" | jq -e '.errors' > /dev/null 2>&1; then
    echo "❌ Shopify API error:"
    echo "$RESPONSE" | jq '.errors'
    echo "$(date -Iseconds) | SHOPIFY_ORDER_FAILED | manual | Error creating order" >> "$AUDIT_LOG"
    exit 1
fi

# Extract order details
SHOPIFY_ORDER_ID=$(echo "$RESPONSE" | jq -r '.order.id')
ORDER_NUMBER=$(echo "$RESPONSE" | jq -r '.order.order_number // .order.name')

if [ -z "$SHOPIFY_ORDER_ID" ] || [ "$SHOPIFY_ORDER_ID" == "null" ]; then
    echo "❌ Failed to create order - no order ID returned"
    echo "$RESPONSE" | jq '.'
    exit 1
fi

# Save to local orders file
ORDER_ID="order_$SHOPIFY_ORDER_ID"

# Initialize orders file if doesn't exist
if [ ! -f "$ORDERS_FILE" ]; then
    echo "{}" > "$ORDERS_FILE"
fi

# Create local order record
NEW_ORDER=$(jq -n \
    --arg id "$ORDER_ID" \
    --arg shopifyId "$SHOPIFY_ORDER_ID" \
    --arg orderNum "$ORDER_NUMBER" \
    --arg name "$NAME" \
    --arg email "$EMAIL" \
    --arg phone "$PHONE" \
    --arg city "$CITY" \
    --arg address "$ADDRESS" \
    --arg postal "$POSTAL" \
    --arg payment "$PAYMENT" \
    --argjson items "$ITEMS" \
    --argjson total "$TOTAL" \
    '{
        id: $id,
        shopifyId: $shopifyId,
        orderNumber: ($orderNum | tostring),
        status: "new",
        source: "manual",
        customer: {
            name: $name,
            email: $email,
            phone: $phone,
            city: $city,
            address: $address,
            postalCode: $postal
        },
        items: $items,
        total: $total,
        currency: "BGN",
        payment: $payment,
        waybill: { tracking: null, done: false },
        shopifyTracking: { done: false },
        invoice: { id: null, done: false },
        email: { sent: false },
        createdAt: (now | todate)
    }')

# Add to orders file
jq --argjson newOrder "$NEW_ORDER" \
    '. + {($newOrder.id): $newOrder}' "$ORDERS_FILE" > "$ORDERS_FILE.tmp" && \
    mv "$ORDERS_FILE.tmp" "$ORDERS_FILE"

# Audit log
echo "$(date -Iseconds) | ORDER_CREATED_SHOPIFY | $ORDER_ID | Manual order #$ORDER_NUMBER" >> "$AUDIT_LOG"

# Output
echo ""
echo "✅ Order created in Shopify!"
echo ""
echo "📦 Order #$ORDER_NUMBER"
echo "🆔 Shopify ID: $SHOPIFY_ORDER_ID"
echo "👤 $NAME"
echo "📱 $PHONE"
echo "📍 $ADDRESS, $POSTAL $CITY"
echo ""
echo "🛒 Items:"
echo "$ITEMS" | jq -r '.[] | "   • \(.qty)x \(.name) @ \(.price) BGN = \(.qty * .price) BGN"'
echo ""
echo "💰 Total: $TOTAL BGN (${PAYMENT^^})"
echo ""
echo "Order ID: $ORDER_ID"
