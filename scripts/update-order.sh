#!/bin/bash
# Update order state
# Usage: bash update-order.sh --order-id ID [--invoice-id X] [--tracking X] [--email-sent] [--status X] [--error X]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="$SCRIPT_DIR/../data"
ORDERS_FILE="$DATA_DIR/orders.json"
AUDIT_LOG="$DATA_DIR/audit.log"

if [ ! -f "$ORDERS_FILE" ]; then
    echo "❌ No orders file found."
    exit 1
fi

# Parse arguments
ORDER_ID=""
INVOICE_ID=""
TRACKING=""
EMAIL_SENT=""
STATUS=""
ERROR=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --order-id) ORDER_ID="$2"; shift 2 ;;
        --invoice-id) INVOICE_ID="$2"; shift 2 ;;
        --tracking) TRACKING="$2"; shift 2 ;;
        --email-sent) EMAIL_SENT="true"; shift ;;
        --status) STATUS="$2"; shift 2 ;;
        --error) ERROR="$2"; shift 2 ;;
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

# Check order exists
ORDER=$(jq -r ".\"$ORDER_ID\"" "$ORDERS_FILE")
if [ "$ORDER" == "null" ]; then
    echo "❌ Order '$ORDER_ID' not found."
    exit 1
fi

# Build jq update expression
JQ_UPDATE=".\"$ORDER_ID\".updatedAt = (now | todate)"

if [ -n "$INVOICE_ID" ]; then
    JQ_UPDATE="$JQ_UPDATE | .\"$ORDER_ID\".invoice.id = \"$INVOICE_ID\" | .\"$ORDER_ID\".invoice.done = true | .\"$ORDER_ID\".status = \"invoice_done\""
    echo "$(date -Iseconds) | INVOICE_UPDATED | $ORDER_ID | Invoice: $INVOICE_ID (manual)" >> "$AUDIT_LOG"
    echo "✅ Invoice updated: $INVOICE_ID"
fi

if [ -n "$TRACKING" ]; then
    JQ_UPDATE="$JQ_UPDATE | .\"$ORDER_ID\".shipment.tracking = \"$TRACKING\" | .\"$ORDER_ID\".shipment.done = true | .\"$ORDER_ID\".status = \"shipment_done\""
    echo "$(date -Iseconds) | SHIPMENT_UPDATED | $ORDER_ID | Tracking: $TRACKING (manual)" >> "$AUDIT_LOG"
    echo "✅ Shipment updated: $TRACKING"
fi

if [ "$EMAIL_SENT" == "true" ]; then
    JQ_UPDATE="$JQ_UPDATE | .\"$ORDER_ID\".email.sent = true | .\"$ORDER_ID\".status = \"completed\""
    echo "$(date -Iseconds) | EMAIL_UPDATED | $ORDER_ID | Marked as sent (manual)" >> "$AUDIT_LOG"
    echo "✅ Email marked as sent"
fi

if [ -n "$STATUS" ]; then
    JQ_UPDATE="$JQ_UPDATE | .\"$ORDER_ID\".status = \"$STATUS\""
    echo "$(date -Iseconds) | STATUS_UPDATED | $ORDER_ID | Status: $STATUS" >> "$AUDIT_LOG"
    echo "✅ Status updated: $STATUS"
fi

if [ -n "$ERROR" ]; then
    JQ_UPDATE="$JQ_UPDATE | .\"$ORDER_ID\".error = \"$ERROR\" | .\"$ORDER_ID\".status = \"failed\""
    echo "$(date -Iseconds) | ERROR_SET | $ORDER_ID | Error: $ERROR" >> "$AUDIT_LOG"
    echo "⚠️ Error recorded: $ERROR"
fi

# Apply update
jq "$JQ_UPDATE" "$ORDERS_FILE" > "$ORDERS_FILE.tmp" && mv "$ORDERS_FILE.tmp" "$ORDERS_FILE"

echo ""
echo "Order $ORDER_ID updated."
