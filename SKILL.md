---
name: cbd-automation
description: Automate CBD shop workflow - Shopify orders → Econt waybill → Shopify tracking → INV24 invoice → Email
---

# CBD Shop Automation

Human-in-the-loop order processing for CBD e-commerce.

## ⚠️ CRITICAL RULES

1. **ALWAYS ask before every step** - [Continue] [Skip] [Cancel]
2. **NEVER proceed without confirmation**
3. **This is someone's business** - be careful!
4. **Invoice MUST be done before email** (email contains the invoice)

## 📦 Order Queue

Orders can stack up. Process them **one by one in order**.

Track queue in `data/queue.json`:
```json
{
  "queue": ["order_123", "order_456", "order_789"],
  "current": "order_123",
  "position": 1
}
```

When showing orders, display: `📦 Order 1/3: #1234`

## 🔄 Workflow (For Each Order)

```
┌─────────────────────────────────────────┐
│  1. NEW ORDER (Shopify webhook)         │
│     Show: order details, paid/COD       │
│     [Start Processing]                  │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│  2. CREATE WAYBILL (Econt API)          │
│     [Continue] [Skip] [Cancel]          │
│                                         │
│     bash scripts/create-shipment.sh     │
│          --order-id ORDER_ID            │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│  3. UPDATE SHOPIFY (add tracking)       │
│     [Continue] [Skip] [Cancel]          │
│                                         │
│     bash scripts/update-shopify-        │
│          tracking.sh --order-id ID      │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│  4. CREATE INVOICE (INV24)              │
│     [Continue] [Skip] [Cancel]          │
│                                         │
│     → Trigger INV24 bot/skill           │
│     → Wait for invoice number           │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│  5. SEND EMAIL (with invoice)           │
│     [Continue] [Skip] [Cancel]          │
│                                         │
│     bash scripts/send-email.sh          │
│          --order-id ORDER_ID            │
│                                         │
│     ⚠️ Requires invoice to be done!     │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│  ✅ MARK AS PROCESSED                   │
│     bash scripts/update-order.sh        │
│          --order-id ID --status done    │
└─────────────────────────────────────────┘
```

## 🔘 Button Actions

| Button | Action |
|--------|--------|
| **Continue** | Execute step, proceed to next |
| **Skip** | Mark step as skipped, proceed to next |
| **Cancel** | Stop workflow, show: [Retry] [Skip to next order] |

### On Cancel:

Show these options:
```
❌ Workflow cancelled for Order #1234

[🔄 Retry] - Start workflow again for this order
[⏭️ Skip to next order] - Mark as "waiting", process next
```

- **Retry**: Reset order to step 1, start workflow again
- **Skip to next order**: 
  - Set order status = "waiting"
  - Remove from queue front
  - Add to end of queue (or separate waiting list)
  - Start processing next order

## 📝 Manual Order (`/manualOrder`)

When user says `/manualOrder` or `manual order`:

### Step 1: Collect Info
```
Bot: 📝 New manual order. Let's collect the info.

     Customer name?
User: Иван Петров

Bot: Phone number?
User: 0888123456

Bot: City?
User: София

Bot: Address?
User: ул. Витоша 15

Bot: Postal code?
User: 1000

Bot: Email? (optional, press Skip if none)
User: ivan@email.com
```

### Step 2: Collect Products (loop)
```
Bot: Product name?
User: CBD масло 10%

Bot: Price per unit (BGN)?
User: 45

Bot: Quantity?
User: 2

Bot: ✅ Added: 2x CBD масло 10% @ 45 = 90 BGN

     Add another product?
     [➕ Add product] [✅ Done]

User: [Add product]
... repeat ...

User: [Done]
```

### Step 3: Confirm & Create in Shopify
```
Bot: 📦 Order Summary:

     👤 Иван Петров
     📱 0888123456
     📧 ivan@email.com
     📍 ул. Витоша 15, 1000 София

     🛒 Items:
        • 2x CBD масло 10% @ 45 = 90 BGN
        • 1x CBD крем @ 35 = 35 BGN
     ─────────────────────────────
     💰 Total: 125 BGN (COD)

     Create order in Shopify?
     [✅ Create] [✏️ Edit] [❌ Cancel]
```

On Create:
```bash
bash scripts/create-shopify-order.sh \
    --name "Иван Петров" \
    --phone "0888123456" \
    --email "ivan@email.com" \
    --city "София" \
    --address "ул. Витоша 15" \
    --postal "1000" \
    --items '[{"name":"CBD масло 10%","qty":2,"price":45},{"name":"CBD крем","qty":1,"price":35}]' \
    --payment "cod"
```

After creation → Order enters queue → Workflow starts automatically.

## 📊 Commands

| User Says | Action |
|-----------|--------|
| `check orders` | Fetch new orders from Shopify |
| `/manualOrder` | Start manual order entry |
| `pending orders` | Show queue + waiting orders |
| `order status <ID>` | Show specific order details |
| `retry order <ID>` | Restart workflow for order |
| `skip order <ID>` | Mark order as waiting, skip |
| `next order` | Process next in queue |
| `setup cbd` | Run configuration setup |

## 📁 Scripts Reference

| Script | Purpose |
|--------|---------|
| `setup.sh` | Interactive configuration |
| `shopify-orders.sh` | Fetch new orders from Shopify |
| `create-shopify-order.sh` | Create manual order IN Shopify |
| `create-shipment.sh` | Create Econt waybill (API) |
| `update-shopify-tracking.sh` | Add tracking to Shopify order |
| `send-email.sh` | Send invoice email to customer |
| `update-order.sh` | Update order status/fields |
| `status.sh` | Check order/queue status |
| `test.sh` | Test service connections |

## 📄 Order Status Values

| Status | Meaning |
|--------|---------|
| `new` | Just received, not started |
| `processing` | Currently in workflow |
| `waiting` | Cancelled/skipped, waiting to retry |
| `processed` | ✅ All steps completed |

## 🗃️ Data Files

| File | Purpose |
|------|---------|
| `data/config.json` | Credentials (encrypted) |
| `data/orders.json` | All orders + their states |
| `data/queue.json` | Current processing queue |
| `data/audit.log` | Action history |

## 🔌 INV24 Integration

INV24 invoice creation is handled by another bot/skill.

When step 4 (invoice) is reached:
1. Prepare invoice data (customer, items, total)
2. Trigger INV24 bot with the data
3. Wait for response with invoice number/PDF
4. Update order with invoice info
5. Proceed to email step

**Data to send to INV24 bot:**
```json
{
  "orderId": "order_123",
  "customer": {
    "name": "Иван Петров",
    "city": "София",
    "address": "ул. Витоша 15"
  },
  "items": [
    {"name": "CBD масло", "qty": 2, "price": 45}
  ],
  "total": 90,
  "payment": "cod"
}
```

## ⚠️ Safety Rules

1. **NEVER** auto-proceed without user confirmation
2. **NEVER** delete orders or data
3. **ALWAYS** log every action to audit.log
4. **ALWAYS** show what you're about to do
5. If email step reached but invoice not done → STOP and inform user
