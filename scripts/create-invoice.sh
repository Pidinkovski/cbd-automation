#!/bin/bash
# Create invoice in INV24
# Usage: bash create-invoice.sh --order-id ORDER_ID
#
# NOTE: INV24 does not have a public API. This script prepares the data
# and provides instructions. The actual invoice can be:
# 1. Created manually in INV24
# 2. Created via browser automation (Playwright) - future enhancement

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
INV_DONE=$(echo "$ORDER" | jq -r '.invoice.done')
if [ "$INV_DONE" == "true" ]; then
    INV_ID=$(echo "$ORDER" | jq -r '.invoice.id')
    echo "⚠️ Invoice already created for this order: $INV_ID"
    exit 0
fi

# Extract order data
ORDER_NUM=$(echo "$ORDER" | jq -r '.orderNumber')
CUSTOMER_NAME=$(echo "$ORDER" | jq -r '.customer.name')
CUSTOMER_PHONE=$(echo "$ORDER" | jq -r '.customer.phone')
CUSTOMER_CITY=$(echo "$ORDER" | jq -r '.customer.city')
CUSTOMER_ADDR=$(echo "$ORDER" | jq -r '.customer.address')
PAYMENT=$(echo "$ORDER" | jq -r '.payment')
TOTAL=$(echo "$ORDER" | jq -r '.total')

# Get business info
COMPANY=$(jq -r '.business.name' "$CONFIG_FILE")
VAT=$(jq -r '.business.vat' "$CONFIG_FILE")

echo "📄 **Invoice Data for Order #$ORDER_NUM**"
echo ""
echo "**Seller:**"
echo "  $COMPANY"
[ "$VAT" != "null" ] && [ -n "$VAT" ] && echo "  VAT: $VAT"
echo ""
echo "**Customer:**"
echo "  $CUSTOMER_NAME"
echo "  $CUSTOMER_ADDR, $CUSTOMER_CITY"
echo "  Tel: $CUSTOMER_PHONE"
echo ""
echo "**Items:**"
echo "$ORDER" | jq -r '.items[] | "  \(.qty)x \(.name) @ \(.price) BGN = \(.qty * .price) BGN"'
echo ""
echo "**Total: $TOTAL BGN**"
echo ""
if [ "$PAYMENT" == "prepaid" ]; then
    echo "💳 Status: **PAID**"
else
    echo "💵 Status: **UNPAID** (Cash on Delivery)"
fi
echo ""
echo "---"
echo ""
echo "⚠️ **INV24 does not have an API.**"
echo ""
echo "Please create the invoice manually in INV24, then tell me the invoice number."
echo ""
echo "Example: \`manual invoice $ORDER_NUM F-0000123\`"
echo ""

# Log attempt
echo "$(date -Iseconds) | INVOICE_PREPARED | $ORDER_ID | Data prepared for manual entry" >> "$AUDIT_LOG"

# TODO: Browser automation with Playwright
# When implemented, this script will:
# 1. Open INV24 in headless browser
# 2. Log in
# 3. Create new invoice with the data above
# 4. Save the invoice number
# 5. Update the order record
