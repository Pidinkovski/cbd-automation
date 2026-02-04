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

## 🔧 Tech Stack

- **Shopify** - Orders & tracking (REST API)
- **Econt** - Waybills (REST API)
- **INV24** - Invoices (Playwright browser automation)
- **Email** - Customer notifications

## 📦 Order Queue

Track queue in `data/queue.json`:
```json
{
  "queue": ["order_123", "order_456"],
  "current": "order_123",
  "position": 1
}
```

When showing orders: `📦 Order 1/3: #1234`

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
│  4. CREATE INVOICE (INV24 Playwright)   │
│     [Continue] [Skip] [Cancel]          │
│                                         │
│     node scripts/create-invoice.js      │
│          --order-file data/order.json   │
│                                         │
│     ⚠️ Uses browser automation!         │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│  5. SEND INVOICE EMAIL                  │
│     [Continue] [Skip] [Cancel]          │
│                                         │
│     node scripts/send-invoice.js        │
│          --invoice-id ID                │
│                                         │
│     Or: bash scripts/send-email.sh      │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│  ✅ MARK AS PROCESSED                   │
│     bash scripts/update-order.sh        │
│          --order-id ID --status done    │
└─────────────────────────────────────────┘
```

## 📄 INV24 Invoice Creation

### Playwright Script
```bash
# Create invoice from order data
node scripts/create-invoice.js --order-json '{
  "client": {
    "name": "Иван Петров",
    "company": "Фирма ЕООД",
    "eik": "123456789",
    "address": "ул. Витоша 15, София",
    "email": "ivan@email.com"
  },
  "items": [
    {"name": "CBD масло 10%", "price": 45, "quantity": 2},
    {"name": "CBD крем", "price": 35, "quantity": 1}
  ]
}'

# Or from file
node scripts/create-invoice.js --order-file data/current-order.json

# With email send
node scripts/create-invoice.js --order-file data/order.json --send
```

### Invoice Types
| Value | Type |
|-------|------|
| 0 | Фактура (Invoice) |
| 1 | Проформа фактура (Proforma) |
| 2 | Ценова оферта (Quote) |
| 3 | Кредитно известие (Credit note) |
| 4 | Дебитно известие (Debit note) |

### Send Existing Invoice
```bash
node scripts/send-invoice.js --invoice-id 1119419
# or
node scripts/send-invoice.js --invoice-number 100000000023
```

## 🔘 Button Actions

| Button | Action |
|--------|--------|
| **Continue** | Execute step, proceed to next |
| **Skip** | Mark step as skipped, proceed to next |
| **Cancel** | Stop workflow, show retry options |

### On Cancel:
```
❌ Workflow cancelled for Order #1234

[🔄 Retry] - Start workflow again
[⏭️ Skip order] - Mark as waiting, process next
```

## 📝 Manual Order (`/manualOrder`)

### Step 1: Collect Info
```
📝 New manual order. Let's collect the info.

Customer name? → Phone? → City? → Address? → Postal code? → Email?
```

### Step 2: Collect Products (loop)
```
Product name? → Price? → Quantity?
✅ Added: 2x CBD масло 10% @ 45 = 90 BGN

[➕ Add product] [✅ Done]
```

### Step 3: Confirm & Create
```
📦 Order Summary:

👤 Иван Петров | 📱 0888123456
📍 ул. Витоша 15, 1000 София

🛒 Items:
   • 2x CBD масло 10% @ 45 = 90 BGN
💰 Total: 90 BGN (COD)

[✅ Create] [✏️ Edit] [❌ Cancel]
```

## 📊 Commands

| User Says | Action |
|-----------|--------|
| `check orders` | Fetch new orders from Shopify |
| `/manualOrder` | Start manual order entry |
| `pending orders` | Show queue + waiting orders |
| `order status <ID>` | Show specific order details |
| `retry order <ID>` | Restart workflow for order |
| `skip order <ID>` | Mark as waiting, skip |
| `next order` | Process next in queue |
| `setup cbd` | Run configuration setup |

## 📁 Scripts Reference

| Script | Purpose |
|--------|---------|
| `setup.sh` | Interactive configuration |
| `shopify-orders.sh` | Fetch new orders from Shopify |
| `create-shopify-order.sh` | Create manual order in Shopify |
| `create-shipment.sh` | Create Econt waybill |
| `update-shopify-tracking.sh` | Add tracking to Shopify |
| **`create-invoice.js`** | **Create INV24 invoice (Playwright)** |
| **`send-invoice.js`** | **Send invoice via INV24 (Playwright)** |
| `send-email.sh` | Send notification email |
| `update-order.sh` | Update order status |
| `status.sh` | Check order/queue status |
| `test.sh` | Test service connections |

## 🗃️ Data Files

| File | Purpose |
|------|---------|
| `data/config.json` | Credentials (⚠️ gitignored) |
| `data/orders.json` | All orders + states |
| `data/queue.json` | Current processing queue |
| `data/audit.log` | Action history |

## ⚙️ Configuration

### INV24 Setup
Credentials stored in `data/config.json`:
```json
{
  "inv24_email": "your@email.com",
  "inv24_password": "yourpassword",
  "invoice_type": "1",
  "default_vat": "20",
  "default_measurement": "бр"
}
```

### Dependencies
```bash
cd skills/cbd-automation
npm install playwright
npx playwright install chromium
npx playwright install-deps chromium
```

## ⚠️ Safety Rules

1. **NEVER** auto-proceed without user confirmation
2. **NEVER** delete orders or data
3. **ALWAYS** log every action to audit.log
4. **ALWAYS** show what you're about to do
5. If email step reached but invoice not done → STOP and inform user
6. INV24 uses browser automation - may take 10-30 seconds per invoice
