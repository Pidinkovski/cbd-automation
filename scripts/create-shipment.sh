#!/bin/bash
# Create Econt shipment
# Usage: bash create-shipment.sh --order-id ORDER_ID

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

# Check if already done
SHIP_DONE=$(echo "$ORDER" | jq -r '.shipment.done')
if [ "$SHIP_DONE" == "true" ]; then
    TRACKING=$(echo "$ORDER" | jq -r '.shipment.tracking')
    echo "⚠️ Shipment already created for this order: $TRACKING"
    exit 0
fi

# Get config
ECONT_USER=$(jq -r '.econt.username' "$CONFIG_FILE")
ECONT_PASS=$(jq -r '.econt.password' "$CONFIG_FILE")
TEST_MODE=$(jq -r '.econt.testMode' "$CONFIG_FILE")

SENDER_NAME=$(jq -r '.econt.sender.name' "$CONFIG_FILE")
SENDER_PHONE=$(jq -r '.econt.sender.phone' "$CONFIG_FILE")
SENDER_CITY=$(jq -r '.econt.sender.city' "$CONFIG_FILE")
SENDER_ADDR=$(jq -r '.econt.sender.address' "$CONFIG_FILE")

# Set base URL
if [ "$TEST_MODE" == "true" ]; then
    BASE_URL="https://demo.econt.com/ee/services"
    echo "⚠️ Using Econt DEMO environment"
else
    BASE_URL="https://ee.econt.com/services"
fi

# Extract order data
ORDER_NUM=$(echo "$ORDER" | jq -r '.orderNumber')
RECEIVER_NAME=$(echo "$ORDER" | jq -r '.customer.name')
RECEIVER_PHONE=$(echo "$ORDER" | jq -r '.customer.phone')
RECEIVER_CITY=$(echo "$ORDER" | jq -r '.customer.city')
RECEIVER_ADDR=$(echo "$ORDER" | jq -r '.customer.address')
RECEIVER_ZIP=$(echo "$ORDER" | jq -r '.customer.postalCode')
PAYMENT=$(echo "$ORDER" | jq -r '.payment')
TOTAL=$(echo "$ORDER" | jq -r '.total')

# Determine COD amount
if [ "$PAYMENT" == "cod" ]; then
    COD_AMOUNT="$TOTAL"
else
    COD_AMOUNT="0"
fi

echo "🚚 Creating Econt shipment for Order #$ORDER_NUM..."
echo ""

# Create shipment request
# Note: This is a simplified request. The actual Econt API requires more fields.
# You may need to adjust based on your specific Econt contract.

REQUEST_BODY=$(cat << EOF
{
  "label": {
    "senderClient": {
      "name": "$SENDER_NAME",
      "phones": ["$SENDER_PHONE"]
    },
    "senderAddress": {
      "city": {
        "name": "$SENDER_CITY",
        "country": {
          "code3": "BGR"
        }
      },
      "street": "$SENDER_ADDR"
    },
    "receiverClient": {
      "name": "$RECEIVER_NAME",
      "phones": ["$RECEIVER_PHONE"]
    },
    "receiverAddress": {
      "city": {
        "name": "$RECEIVER_CITY",
        "postCode": "$RECEIVER_ZIP",
        "country": {
          "code3": "BGR"
        }
      },
      "street": "$RECEIVER_ADDR"
    },
    "packCount": 1,
    "shipmentType": "PACK",
    "weight": 0.5,
    "shipmentDescription": "Order $ORDER_NUM",
    "services": {
      "cdAmount": $COD_AMOUNT,
      "cdType": "GET",
      "cdCurrency": "BGN"
    },
    "paymentSenderMethod": "CASH",
    "paymentReceiverMethod": "$( [ "$PAYMENT" == "cod" ] && echo "CASH" || echo "NO" )"
  },
  "mode": "create"
}
EOF
)

echo "📦 Shipment details:"
echo "  From: $SENDER_NAME, $SENDER_CITY"
echo "  To: $RECEIVER_NAME, $RECEIVER_CITY"
echo "  COD: $COD_AMOUNT BGN"
echo ""

# Make API request
RESPONSE=$(curl -s -X POST "$BASE_URL/Shipments/LabelService.createLabel.json" \
    -u "$ECONT_USER:$ECONT_PASS" \
    -H "Content-Type: application/json" \
    -d "$REQUEST_BODY")

# Check response
if echo "$RESPONSE" | jq -e '.label.shipmentNumber' > /dev/null 2>&1; then
    TRACKING=$(echo "$RESPONSE" | jq -r '.label.shipmentNumber')
    
    # Update order (use waybill field)
    jq ".\"$ORDER_ID\".waybill.tracking = \"$TRACKING\" | .\"$ORDER_ID\".waybill.done = true | .\"$ORDER_ID\".shipment.tracking = \"$TRACKING\" | .\"$ORDER_ID\".shipment.done = true" \
        "$ORDERS_FILE" > "$ORDERS_FILE.tmp" && mv "$ORDERS_FILE.tmp" "$ORDERS_FILE"
    
    # Audit log
    echo "$(date -Iseconds) | SHIPMENT_CREATED | $ORDER_ID | Tracking: $TRACKING" >> "$AUDIT_LOG"
    
    echo "✅ Shipment created!"
    echo ""
    echo "📦 Tracking number: **$TRACKING**"
    echo "🔗 Track: https://www.econt.com/services/track-shipment?shipmentNumber=$TRACKING"
    
else
    # Error
    ERROR=$(echo "$RESPONSE" | jq -r '.error.message // .message // "Unknown error"')
    echo "$(date -Iseconds) | SHIPMENT_FAILED | $ORDER_ID | Error: $ERROR" >> "$AUDIT_LOG"
    
    echo "❌ Failed to create shipment"
    echo "Error: $ERROR"
    echo ""
    echo "Full response:"
    echo "$RESPONSE" | jq '.'
    exit 1
fi
