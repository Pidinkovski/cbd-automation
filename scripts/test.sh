#!/bin/bash
# Test service connections
# Usage: bash test.sh --service [shopify|inv24|econt|email|all]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="$SCRIPT_DIR/../data"
CONFIG_FILE="$DATA_DIR/config.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Config not found. Run setup.sh first."
    exit 1
fi

# Parse arguments
SERVICE="all"
while [[ $# -gt 0 ]]; do
    case $1 in
        --service) SERVICE="$2"; shift 2 ;;
        *) shift ;;
    esac
done

test_shopify() {
    echo "🔄 Testing Shopify connection..."
    
    STORE=$(jq -r '.shopify.store' "$CONFIG_FILE")
    TOKEN=$(jq -r '.shopify.accessToken' "$CONFIG_FILE")
    
    if [ -z "$STORE" ] || [ "$STORE" == "null" ]; then
        echo "  ❌ Store URL not configured"
        return 1
    fi
    
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
        "https://$STORE/admin/api/2024-01/shop.json" \
        -H "X-Shopify-Access-Token: $TOKEN")
    
    if [ "$RESPONSE" == "200" ]; then
        echo "  ✅ Shopify connected! Store: $STORE"
        return 0
    else
        echo "  ❌ Shopify connection failed (HTTP $RESPONSE)"
        return 1
    fi
}

test_econt() {
    echo "🔄 Testing Econt connection..."
    
    USER=$(jq -r '.econt.username' "$CONFIG_FILE")
    PASS=$(jq -r '.econt.password' "$CONFIG_FILE")
    TEST_MODE=$(jq -r '.econt.testMode' "$CONFIG_FILE")
    
    if [ -z "$USER" ] || [ "$USER" == "null" ]; then
        echo "  ❌ Econt username not configured"
        return 1
    fi
    
    # Use demo or production URL
    if [ "$TEST_MODE" == "true" ]; then
        BASE_URL="https://demo.econt.com/ee/services"
        echo "  ℹ️  Using Econt DEMO environment"
    else
        BASE_URL="https://ee.econt.com/services"
    fi
    
    # Test with GetClientProfiles endpoint
    RESPONSE=$(curl -s -X POST "$BASE_URL/Profile/ProfileService.getClientProfiles.json" \
        -u "$USER:$PASS" \
        -H "Content-Type: application/json" \
        -d '{}')
    
    if echo "$RESPONSE" | jq -e '.profiles' > /dev/null 2>&1; then
        PROFILE_COUNT=$(echo "$RESPONSE" | jq '.profiles | length')
        echo "  ✅ Econt connected! Found $PROFILE_COUNT profile(s)"
        return 0
    else
        ERROR=$(echo "$RESPONSE" | jq -r '.error.message // .message // "Unknown error"')
        echo "  ❌ Econt connection failed: $ERROR"
        return 1
    fi
}

test_inv24() {
    echo "🔄 Testing INV24..."
    
    EMAIL=$(jq -r '.inv24.email' "$CONFIG_FILE")
    
    if [ -z "$EMAIL" ] || [ "$EMAIL" == "null" ]; then
        echo "  ❌ INV24 email not configured"
        return 1
    fi
    
    # INV24 doesn't have API, just check config exists
    echo "  ℹ️  INV24 configured with: $EMAIL"
    echo "  ℹ️  Note: INV24 requires browser automation or manual entry"
    echo "  ✅ Config OK (no API to test)"
    return 0
}

test_email() {
    echo "🔄 Testing Email (SMTP)..."
    
    HOST=$(jq -r '.email.smtp.host' "$CONFIG_FILE")
    PORT=$(jq -r '.email.smtp.port' "$CONFIG_FILE")
    USER=$(jq -r '.email.username' "$CONFIG_FILE")
    
    if [ -z "$HOST" ] || [ "$HOST" == "null" ]; then
        echo "  ❌ SMTP host not configured"
        return 1
    fi
    
    # Test SMTP connection with timeout
    if timeout 5 bash -c "echo > /dev/tcp/$HOST/$PORT" 2>/dev/null; then
        echo "  ✅ SMTP reachable: $HOST:$PORT"
        echo "  ℹ️  User: $USER"
        return 0
    else
        echo "  ❌ Cannot connect to $HOST:$PORT"
        return 1
    fi
}

# Run tests
echo "🧪 Testing CBD Automation Services"
echo "==================================="
echo ""

FAILED=0

case "$SERVICE" in
    shopify)
        test_shopify || FAILED=1
        ;;
    econt)
        test_econt || FAILED=1
        ;;
    inv24)
        test_inv24 || FAILED=1
        ;;
    email)
        test_email || FAILED=1
        ;;
    all)
        test_shopify || FAILED=1
        echo ""
        test_inv24 || FAILED=1
        echo ""
        test_econt || FAILED=1
        echo ""
        test_email || FAILED=1
        ;;
    *)
        echo "Unknown service: $SERVICE"
        echo "Use: shopify, inv24, econt, email, or all"
        exit 1
        ;;
esac

echo ""
if [ $FAILED -eq 0 ]; then
    echo "✅ All tests passed!"
else
    echo "⚠️ Some tests failed. Check configuration."
fi

exit $FAILED
