#!/bin/bash
# Update Shopify order with tracking number (after Econt waybill created)
# Usage: bash update-shopify-tracking.sh --order-id ORDER_ID

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="$SCRIPT_DIR/../data"
CONFIG_FILE="$DATA_DIR/config.json"
ORDERS_FILE="$DATA_DIR/orders.json"
AUDIT_LOG="$DATA_DIR/audit.log"

if [ ! -f "$CONFIG_FILE" ] || [ ! -f "$ORDERS_FILE" ]; then
    echo "❌ Config or orders file not found."
    exit 1
fi

# Parse arguments
ORDER_ID=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --order-id) ORDER_ID="$2"; shift 2 ;;
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

# Check if tracking already updated in Shopify
TRACKING_DONE=$(echo "$ORDER" | jq -r '.shopifyTracking.done // false')
if [ "$TRACKING_DONE" == "true" ]; then
    echo "⚠️ Tracking already updated in Shopify for this order."
    exit 0
fi

# Get tracking number from waybill
TRACKING=$(echo "$ORDER" | jq -r '.waybill.tracking // .shipment.tracking // null')
if [ -z "$TRACKING" ] || [ "$TRACKING" == "null" ]; then
    echo "❌ No tracking number found. Create Econt waybill first."
    exit 1
fi

# Get Shopify details
SHOPIFY_ORDER_ID=$(echo "$ORDER" | jq -r '.shopifyId')
ORDER_NUM=$(echo "$ORDER" | jq -r '.orderNumber')

if [ -z "$SHOPIFY_ORDER_ID" ] || [ "$SHOPIFY_ORDER_ID" == "null" ]; then
    echo "❌ No Shopify order ID found."
    exit 1
fi

# Get Shopify config
STORE=$(jq -r '.shopify.store' "$CONFIG_FILE")
TOKEN=$(jq -r '.shopify.accessToken' "$CONFIG_FILE")

echo "🔄 Updating Shopify order #$ORDER_NUM with tracking..."
echo "   Tracking: $TRACKING"

# First, we need to get the fulfillment order ID
# In Shopify's newer API, we need to:
# 1. Get fulfillment orders
# 2. Create a fulfillment with tracking

# Step 1: Get fulfillment orders for this order
FULFILLMENT_ORDERS=$(curl -s -X GET \
    "https://$STORE/admin/api/2024-01/orders/$SHOPIFY_ORDER_ID/fulfillment_orders.json" \
    -H "X-Shopify-Access-Token: $TOKEN" \
    -H "Content-Type: application/json")

FULFILLMENT_ORDER_ID=$(echo "$FULFILLMENT_ORDERS" | jq -r '.fulfillment_orders[0].id // null')

if [ -z "$FULFILLMENT_ORDER_ID" ] || [ "$FULFILLMENT_ORDER_ID" == "null" ]; then
    # Fallback: Try legacy fulfillments API
    echo "   Using legacy fulfillment API..."
    
    FULFILLMENT_JSON=$(cat << EOF
{
  "fulfillment": {
    "location_id": null,
    "tracking_number": "$TRACKING",
    "tracking_company": "Econt",
    "tracking_url": "https://www.econt.com/services/track-shipment?shipmentNumber=$TRACKING",
    "notify_customer": false
  }
}
EOF
)

    RESPONSE=$(curl -s -X POST \
        "https://$STORE/admin/api/2024-01/orders/$SHOPIFY_ORDER_ID/fulfillments.json" \
        -H "X-Shopify-Access-Token: $TOKEN" \
        -H "Content-Type: application/json" \
        -d "$FULFILLMENT_JSON")
else
    # Use new fulfillment API
    echo "   Using fulfillment orders API..."
    
    # Get line items from fulfillment order
    LINE_ITEMS=$(echo "$FULFILLMENT_ORDERS" | jq '[.fulfillment_orders[0].line_items[] | {id: .id, quantity: .quantity}]')
    
    FULFILLMENT_JSON=$(cat << EOF
{
  "fulfillment": {
    "line_items_by_fulfillment_order": [
      {
        "fulfillment_order_id": $FULFILLMENT_ORDER_ID,
        "fulfillment_order_line_items": $LINE_ITEMS
      }
    ],
    "tracking_info": {
      "number": "$TRACKING",
      "company": "Econt",
      "url": "https://www.econt.com/services/track-shipment?shipmentNumber=$TRACKING"
    },
    "notify_customer": false
  }
}
EOF
)

    RESPONSE=$(curl -s -X POST \
        "https://$STORE/admin/api/2024-01/fulfillments.json" \
        -H "X-Shopify-Access-Token: $TOKEN" \
        -H "Content-Type: application/json" \
        -d "$FULFILLMENT_JSON")
fi

# Check response
if echo "$RESPONSE" | jq -e '.fulfillment.id' > /dev/null 2>&1; then
    FULFILLMENT_ID=$(echo "$RESPONSE" | jq -r '.fulfillment.id')
    
    # Update local order
    jq ".\"$ORDER_ID\".shopifyTracking.done = true | .\"$ORDER_ID\".shopifyTracking.fulfillmentId = \"$FULFILLMENT_ID\"" \
        "$ORDERS_FILE" > "$ORDERS_FILE.tmp" && mv "$ORDERS_FILE.tmp" "$ORDERS_FILE"
    
    echo "$(date -Iseconds) | SHOPIFY_TRACKING_UPDATED | $ORDER_ID | Tracking: $TRACKING" >> "$AUDIT_LOG"
    
    echo ""
    echo "✅ Shopify updated!"
    echo "   Fulfillment ID: $FULFILLMENT_ID"
    echo "   Tracking: $TRACKING"
    echo "   🔗 https://www.econt.com/services/track-shipment?shipmentNumber=$TRACKING"

elif echo "$RESPONSE" | jq -e '.errors' > /dev/null 2>&1; then
    ERROR=$(echo "$RESPONSE" | jq -r '.errors | if type == "object" then to_entries | map("\(.key): \(.value | join(", "))") | join("; ") else tostring end')
    echo "$(date -Iseconds) | SHOPIFY_TRACKING_FAILED | $ORDER_ID | Error: $ERROR" >> "$AUDIT_LOG"
    
    echo "❌ Failed to update Shopify"
    echo "   Error: $ERROR"
    exit 1
else
    echo "$(date -Iseconds) | SHOPIFY_TRACKING_FAILED | $ORDER_ID | Unknown error" >> "$AUDIT_LOG"
    echo "❌ Unexpected response from Shopify:"
    echo "$RESPONSE" | jq '.'
    exit 1
fi
