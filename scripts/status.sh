#!/bin/bash
# Check order status
# Usage: bash status.sh [--order-id ID] [--pending] [--failed] [--all]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="$SCRIPT_DIR/../data"
ORDERS_FILE="$DATA_DIR/orders.json"

if [ ! -f "$ORDERS_FILE" ]; then
    echo "📭 No orders yet."
    exit 0
fi

# Parse arguments
ORDER_ID=""
FILTER=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --order-id) ORDER_ID="$2"; shift 2 ;;
        --pending) FILTER="pending"; shift ;;
        --failed) FILTER="failed"; shift ;;
        --completed) FILTER="completed"; shift ;;
        --all) FILTER="all"; shift ;;
        *) shift ;;
    esac
done

# Function to format order
format_order() {
    local order="$1"
    local id=$(echo "$order" | jq -r '.id')
    local num=$(echo "$order" | jq -r '.orderNumber')
    local name=$(echo "$order" | jq -r '.customer.name')
    local phone=$(echo "$order" | jq -r '.customer.phone')
    local city=$(echo "$order" | jq -r '.customer.city')
    local address=$(echo "$order" | jq -r '.customer.address')
    local total=$(echo "$order" | jq -r '.total')
    local currency=$(echo "$order" | jq -r '.currency')
    local payment=$(echo "$order" | jq -r '.payment')
    local status=$(echo "$order" | jq -r '.status')
    
    local inv_done=$(echo "$order" | jq -r '.invoice.done')
    local inv_id=$(echo "$order" | jq -r '.invoice.id // "-"')
    local ship_done=$(echo "$order" | jq -r '.shipment.done')
    local ship_id=$(echo "$order" | jq -r '.shipment.tracking // "-"')
    local email_done=$(echo "$order" | jq -r '.email.sent')
    
    # Status emojis
    inv_emoji="⏳"; [ "$inv_done" == "true" ] && inv_emoji="✅"
    ship_emoji="⏳"; [ "$ship_done" == "true" ] && ship_emoji="✅"
    email_emoji="⏳"; [ "$email_done" == "true" ] && email_emoji="✅"
    
    echo "📦 **Order #$num** ($id)"
    echo ""
    echo "👤 $name"
    echo "📱 $phone"
    echo "📍 $address, $city"
    echo ""
    echo "🛒 Items:"
    echo "$order" | jq -r '.items[] | "   • \(.qty)x \(.name) - \(.price) BGN"'
    echo ""
    echo "💰 Total: $total $currency (${payment^^})"
    echo ""
    echo "Status:"
    echo "  $inv_emoji Invoice: $inv_id"
    echo "  $ship_emoji Shipment: $ship_id"
    echo "  $email_emoji Email"
}

# Single order lookup
if [ -n "$ORDER_ID" ]; then
    # Try to find by exact ID or order number
    ORDER=$(jq -r ".[\"$ORDER_ID\"] // .[\"order_$ORDER_ID\"] // (to_entries[] | select(.value.orderNumber == \"$ORDER_ID\") | .value) // null" "$ORDERS_FILE")
    
    if [ "$ORDER" == "null" ] || [ -z "$ORDER" ]; then
        echo "❌ Order '$ORDER_ID' not found."
        exit 1
    fi
    
    format_order "$ORDER"
    exit 0
fi

# List orders by filter
case "$FILTER" in
    pending)
        echo "📋 **Pending Orders**"
        echo ""
        jq -r 'to_entries[] | select(.value.invoice.done == false or .value.shipment.done == false or .value.email.sent == false) | .value | "• #\(.orderNumber) - \(.customer.name) - \(.total) \(.currency)"' "$ORDERS_FILE"
        ;;
    failed)
        echo "❌ **Failed Orders**"
        echo ""
        jq -r 'to_entries[] | select(.value.status == "failed") | .value | "• #\(.orderNumber) - \(.customer.name) - Error: \(.error // "unknown")"' "$ORDERS_FILE"
        ;;
    completed)
        echo "✅ **Completed Orders**"
        echo ""
        jq -r 'to_entries[] | select(.value.invoice.done == true and .value.shipment.done == true and .value.email.sent == true) | .value | "• #\(.orderNumber) - \(.customer.name) - \(.total) \(.currency)"' "$ORDERS_FILE"
        ;;
    all|*)
        echo "📦 **All Orders**"
        echo ""
        jq -r 'to_entries[] | .value | "• #\(.orderNumber) - \(.customer.name) - \(.total) \(.currency) - \(.status)"' "$ORDERS_FILE"
        ;;
esac

# Count
TOTAL=$(jq 'length' "$ORDERS_FILE")
PENDING=$(jq '[to_entries[] | select(.value.invoice.done == false or .value.shipment.done == false)] | length' "$ORDERS_FILE")
echo ""
echo "Total: $TOTAL | Pending: $PENDING"
