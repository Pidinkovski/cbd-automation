#!/bin/bash
# Fetch new orders from Shopify
# Usage: bash shopify-orders.sh [--since HOURS]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="$SCRIPT_DIR/../data"
CONFIG_FILE="$DATA_DIR/config.json"
ORDERS_FILE="$DATA_DIR/orders.json"

# Check config exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Config not found. Run setup.sh first."
    exit 1
fi

# Parse arguments
SINCE_HOURS=24
while [[ $# -gt 0 ]]; do
    case $1 in
        --since) SINCE_HOURS="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Read config
STORE=$(jq -r '.shopify.store' "$CONFIG_FILE")
TOKEN=$(jq -r '.shopify.accessToken' "$CONFIG_FILE")

if [ -z "$STORE" ] || [ "$STORE" == "null" ]; then
    echo "❌ Shopify store not configured"
    exit 1
fi

# Calculate date for filtering
SINCE_DATE=$(date -u -d "$SINCE_HOURS hours ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-${SINCE_HOURS}H +%Y-%m-%dT%H:%M:%SZ)

# Fetch orders from Shopify
echo "🔄 Fetching orders from Shopify (last $SINCE_HOURS hours)..."

RESPONSE=$(curl -s -X GET \
    "https://$STORE/admin/api/2024-01/orders.json?status=any&created_at_min=$SINCE_DATE&limit=50" \
    -H "X-Shopify-Access-Token: $TOKEN" \
    -H "Content-Type: application/json")

# Check for errors
if echo "$RESPONSE" | jq -e '.errors' > /dev/null 2>&1; then
    echo "❌ Shopify API error:"
    echo "$RESPONSE" | jq '.errors'
    exit 1
fi

# Parse orders
ORDERS=$(echo "$RESPONSE" | jq '.orders')
ORDER_COUNT=$(echo "$ORDERS" | jq 'length')

if [ "$ORDER_COUNT" == "0" ]; then
    echo "📭 No new orders in the last $SINCE_HOURS hours."
    exit 0
fi

echo "📦 Found $ORDER_COUNT order(s):"
echo ""

# Initialize orders file if doesn't exist
if [ ! -f "$ORDERS_FILE" ]; then
    echo "{}" > "$ORDERS_FILE"
fi

# Process each order
NEW_COUNT=0
echo "$ORDERS" | jq -c '.[]' | while read -r order; do
    ORDER_ID=$(echo "$order" | jq -r '.id')
    ORDER_NUM=$(echo "$order" | jq -r '.order_number // .name')
    CUSTOMER_NAME=$(echo "$order" | jq -r '(.customer.first_name // "") + " " + (.customer.last_name // "")' | xargs)
    CUSTOMER_EMAIL=$(echo "$order" | jq -r '.customer.email // .email // ""')
    TOTAL=$(echo "$order" | jq -r '.total_price')
    CURRENCY=$(echo "$order" | jq -r '.currency // "BGN"')
    FINANCIAL_STATUS=$(echo "$order" | jq -r '.financial_status')
    
    # Determine payment method
    if [ "$FINANCIAL_STATUS" == "paid" ]; then
        PAYMENT="prepaid"
    else
        PAYMENT="cod"
    fi
    
    # Check if already tracked
    EXISTING=$(jq -r ".\"order_$ORDER_ID\"" "$ORDERS_FILE")
    if [ "$EXISTING" != "null" ]; then
        echo "  ⏭️  #$ORDER_NUM - Already tracked"
        continue
    fi
    
    # Extract shipping address
    SHIP_NAME=$(echo "$order" | jq -r '.shipping_address.name // ""')
    SHIP_PHONE=$(echo "$order" | jq -r '.shipping_address.phone // .customer.phone // ""')
    SHIP_CITY=$(echo "$order" | jq -r '.shipping_address.city // ""')
    SHIP_ADDR=$(echo "$order" | jq -r '(.shipping_address.address1 // "") + " " + (.shipping_address.address2 // "")' | xargs)
    SHIP_ZIP=$(echo "$order" | jq -r '.shipping_address.zip // ""')
    
    # Extract items
    ITEMS=$(echo "$order" | jq '[.line_items[] | {name: .name, qty: .quantity, price: (.price | tonumber)}]')
    
    # Add to orders file
    NEW_ORDER=$(jq -n \
        --arg id "order_$ORDER_ID" \
        --arg shopifyId "$ORDER_ID" \
        --arg orderNum "$ORDER_NUM" \
        --arg name "$CUSTOMER_NAME" \
        --arg email "$CUSTOMER_EMAIL" \
        --arg phone "$SHIP_PHONE" \
        --arg city "$SHIP_CITY" \
        --arg address "$SHIP_ADDR" \
        --arg postal "$SHIP_ZIP" \
        --arg total "$TOTAL" \
        --arg currency "$CURRENCY" \
        --arg payment "$PAYMENT" \
        --argjson items "$ITEMS" \
        '{
            id: $id,
            shopifyId: $shopifyId,
            orderNumber: $orderNum,
            status: "new",
            customer: {
                name: $name,
                email: $email,
                phone: $phone,
                city: $city,
                address: $address,
                postalCode: $postal
            },
            items: $items,
            total: ($total | tonumber),
            currency: $currency,
            payment: $payment,
            invoice: { id: null, done: false },
            shipment: { tracking: null, done: false },
            email: { sent: false },
            createdAt: (now | todate)
        }')
    
    # Merge into orders file
    jq --argjson newOrder "$NEW_ORDER" \
        '. + {($newOrder.id): $newOrder}' "$ORDERS_FILE" > "$ORDERS_FILE.tmp" && \
        mv "$ORDERS_FILE.tmp" "$ORDERS_FILE"
    
    echo "  📦 #$ORDER_NUM - $CUSTOMER_NAME - $TOTAL $CURRENCY ($PAYMENT)"
    NEW_COUNT=$((NEW_COUNT + 1))
done

echo ""
echo "✅ Done. Use 'pending orders' to see orders awaiting processing."
