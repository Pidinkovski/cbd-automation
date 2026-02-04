# CBD Automation - Installation Guide

This document explains how to set up a fresh Clawdbot instance for CBD shop automation.

## 📋 Prerequisites

- Ubuntu 22.04+ or Debian 12+
- Node.js 18+ 
- Clawdbot installed and running
- Internet access for API calls

## 🔧 Required Skills

### 1. CBD Automation Skill (this one)
Copy this entire skill folder to your bot's workspace:
```bash
cp -r skills/cbd-automation /path/to/your/clawd/skills/
```

### 2. No Additional Clawdbot Skills Required
This skill is self-contained. However, these **built-in Clawdbot capabilities** are used:
- `exec` - Running shell scripts
- `read/write` - File operations
- `message` - Telegram notifications

## 📦 System Dependencies

### Playwright Browser Automation
Required for INV24 invoice creation:

```bash
# Install Playwright npm package
cd /path/to/clawd/skills/cbd-automation
npm install playwright

# Download Chromium browser
npx playwright install chromium

# Install system dependencies for Chromium
npx playwright install-deps chromium
```

### System packages (if playwright install-deps fails)
```bash
sudo apt update
sudo apt install -y \
  libnss3 \
  libnspr4 \
  libatk1.0-0 \
  libatk-bridge2.0-0 \
  libcups2 \
  libdrm2 \
  libxkbcommon0 \
  libxcomposite1 \
  libxdamage1 \
  libxfixes3 \
  libxrandr2 \
  libgbm1 \
  libasound2 \
  libpango-1.0-0 \
  libcairo2 \
  libfontconfig1
```

## ⚙️ Configuration

### 1. Create config file
```bash
mkdir -p skills/cbd-automation/data
cat > skills/cbd-automation/data/config.json << 'EOF'
{
  "inv24_email": "YOUR_INV24_EMAIL",
  "inv24_password": "YOUR_INV24_PASSWORD",
  "invoice_type": "1",
  "default_vat": "20",
  "default_measurement": "бр",
  
  "shopify_store": "YOUR_STORE.myshopify.com",
  "shopify_api_key": "YOUR_API_KEY",
  "shopify_api_secret": "YOUR_API_SECRET",
  
  "econt_username": "YOUR_ECONT_USER",
  "econt_password": "YOUR_ECONT_PASS",
  
  "smtp_host": "smtp.gmail.com",
  "smtp_port": 587,
  "smtp_user": "YOUR_EMAIL",
  "smtp_pass": "YOUR_APP_PASSWORD",
  "email_from": "Your Shop <shop@example.com>"
}
EOF
```

### 2. Protect credentials
Make sure `.gitignore` includes:
```
data/config.json
```

## 🧪 Test Installation

### Test INV24 connection
```bash
cd skills/cbd-automation
node scripts/create-invoice.js --order-json '{
  "client": {"name": "Test", "company": "Test Co", "address": "Test St"},
  "items": [{"name": "Test Product", "price": 10, "quantity": 1}]
}'
```

Expected output:
```
✅ Invoice created successfully!
```

### Test Shopify connection
```bash
bash scripts/shopify-orders.sh --test
```

### Test Econt connection
```bash
bash scripts/test.sh
```

## 📁 File Structure

```
skills/cbd-automation/
├── SKILL.md           # Main skill documentation
├── INSTALL.md         # This file
├── package.json       # Node.js dependencies
├── data/
│   ├── config.json    # Credentials (gitignored!)
│   ├── orders.json    # Order database
│   ├── queue.json     # Processing queue
│   └── audit.log      # Action log
├── scripts/
│   ├── create-invoice.js      # INV24 Playwright
│   ├── send-invoice.js        # INV24 email send
│   ├── shopify-orders.sh      # Fetch orders
│   ├── create-shipment.sh     # Econt waybill
│   ├── update-shopify-tracking.sh
│   ├── send-email.sh          # SMTP email
│   └── ...
└── templates/
    ├── email.html
    └── email.txt
```

## 🔐 API Credentials Needed

| Service | What You Need | Where to Get It |
|---------|---------------|-----------------|
| **INV24** | Email + Password | Your INV24 account |
| **Shopify** | API Key + Secret | Shopify Admin → Apps → Develop apps |
| **Econt** | Username + Password | Econt business account |
| **SMTP** | Email + App Password | Gmail: Security → App passwords |

## 🚀 Quick Start After Install

1. Copy skill to workspace
2. Run `npm install playwright` in skill folder
3. Run `npx playwright install chromium`
4. Run `npx playwright install-deps chromium`
5. Create `data/config.json` with credentials
6. Test with `node scripts/create-invoice.js`

## ⚠️ Troubleshooting

### "Cannot find module 'playwright'"
```bash
cd skills/cbd-automation && npm install playwright
```

### "Executable doesn't exist" (Chromium)
```bash
npx playwright install chromium
```

### "libnspr4.so: cannot open shared object"
```bash
npx playwright install-deps chromium
# or manually: sudo apt install libnss3 libnspr4
```

### INV24 login fails
- Check credentials in config.json
- Try logging in manually at inv24.com
- Check if account is locked

### Playwright timeout
- INV24 may be slow - increase timeout
- Check internet connection
- Run with `--debug` flag to see browser

## 📞 Support

If issues persist:
1. Check `data/audit.log` for errors
2. Run scripts with `--debug` flag
3. Test each service individually
