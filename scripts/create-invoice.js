#!/usr/bin/env node
/**
 * INV24 Invoice Creator via Playwright
 * Creates invoices automatically in INV24.com
 * 
 * Usage: node create-invoice.js --order-json '{"client":...,"items":...}'
 * Or:    node create-invoice.js --order-file /path/to/order.json
 */

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

// Config
const CONFIG_PATH = path.join(__dirname, '../data/config.json');
const DEFAULT_CONFIG = {
  inv24_email: process.env.INV24_EMAIL || '',
  inv24_password: process.env.INV24_PASSWORD || '',
  invoice_type: '1', // 0=Фактура, 1=Проформа, 2=Оферта, 3=Кредитно, 4=Дебитно
  default_vat: '20',
  default_measurement: 'бр'
};

function loadConfig() {
  try {
    if (fs.existsSync(CONFIG_PATH)) {
      return { ...DEFAULT_CONFIG, ...JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8')) };
    }
  } catch (e) {}
  return DEFAULT_CONFIG;
}

function parseArgs() {
  const args = process.argv.slice(2);
  const result = {};
  
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--order-json' && args[i + 1]) {
      result.orderJson = args[++i];
    } else if (args[i] === '--order-file' && args[i + 1]) {
      result.orderFile = args[++i];
    } else if (args[i] === '--send') {
      result.sendEmail = true;
    } else if (args[i] === '--type' && args[i + 1]) {
      result.invoiceType = args[++i];
    } else if (args[i] === '--debug') {
      result.debug = true;
    }
  }
  
  return result;
}

async function createInvoice(orderData, options = {}) {
  const config = loadConfig();
  
  if (!config.inv24_email || !config.inv24_password) {
    throw new Error('INV24 credentials not configured. Run setup first.');
  }
  
  const invoiceType = options.invoiceType || config.invoice_type || '1';
  
  console.log('🚀 Starting INV24 invoice creation...');
  
  const browser = await chromium.launch({
    headless: !options.debug,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });
  
  const page = await browser.newPage();
  let result = { success: false };
  
  try {
    // Step 1: Login
    console.log('📝 Logging in to INV24...');
    await page.goto('https://www.inv24.com/bg/');
    await page.fill('input[name="userLogin"]', config.inv24_email);
    await page.fill('input[name="userPassword"]', config.inv24_password);
    await page.click('input[name="submit"]');
    await page.waitForURL(/viewManage|invoices/, { timeout: 15000 });
    console.log('✅ Logged in');
    
    // Step 2: Go to new invoice form with type preselected
    console.log('📝 Opening new invoice form...');
    await page.goto(`https://www.inv24.com/index.php?lang=bg&class=invoices&action=viewAdd&invoice_type=${invoiceType}`);
    await page.waitForLoadState('networkidle');
    
    // Step 3: Fill client info
    console.log('📝 Filling client info...');
    const client = orderData.client || orderData.customer || {};
    
    if (client.name) await page.fill('input[name="receiver"]', client.name);
    if (client.company) await page.fill('input[name="client_name"]', client.company);
    else if (client.name) await page.fill('input[name="client_name"]', client.name);
    
    if (client.eik || client.personal_code) {
      await page.fill('input[name="client_personal_code"]', client.eik || client.personal_code || '');
    }
    if (client.vat_number) {
      await page.fill('input[name="client_vat_number"]', client.vat_number);
    }
    if (client.address) {
      await page.fill('textarea[name="client_address"]', client.address);
    }
    if (client.email) {
      await page.fill('input[name="client_email"]', client.email);
    }
    
    // Step 4: Add products
    console.log('📝 Adding products...');
    const items = orderData.items || orderData.products || orderData.line_items || [];
    
    for (const item of items) {
      const name = item.name || item.title || 'Product';
      const price = item.price || item.unit_price || '0';
      const qty = item.quantity || item.qty || '1';
      const vat = item.vat || config.default_vat;
      const unit = item.measurement || item.unit || config.default_measurement;
      
      await page.fill('input[name="g_name"]', name);
      await page.fill('input[name="g_price"]', String(price));
      await page.fill('input[name="g_quantity"]', String(qty));
      await page.fill('input[name="g_vat"]', String(vat));
      await page.fill('input[name="g_measurement"]', unit);
      
      // Click add button
      await page.click('input.lisaToote');
      await page.waitForTimeout(500);
      
      console.log(`  ✅ Added: ${qty}x ${name} @ ${price}`);
    }
    
    // Step 5: Submit invoice
    console.log('📝 Submitting invoice...');
    await page.click('input[name="save_button"]');
    await page.waitForTimeout(3000);
    
    const finalUrl = page.url();
    const content = await page.content();
    
    if (finalUrl.includes('viewManage') || content.includes('успешно')) {
      console.log('✅ Invoice created successfully!');
      
      // Try to extract invoice number
      const invoiceMatch = content.match(/100[0-9]{10}/);
      if (invoiceMatch) {
        result.invoiceNumber = invoiceMatch[0];
        console.log(`📄 Invoice number: ${result.invoiceNumber}`);
      }
      
      result.success = true;
      result.url = finalUrl;
      
      // Step 6: Send email if requested
      if (options.sendEmail && client.email) {
        console.log('📧 Sending invoice email...');
        // Find and click send button for the new invoice
        // This would need the invoice ID from the list
        // For now, we'll note it should be sent manually or in a follow-up
        result.emailPending = true;
        console.log('⚠️ Email sending requires invoice ID - check INV24 manually or implement send step');
      }
      
    } else {
      console.log('❌ Invoice creation may have failed');
      console.log('Final URL:', finalUrl);
      result.error = 'Form submission did not redirect to success page';
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    result.error = error.message;
  } finally {
    await browser.close();
  }
  
  return result;
}

// Main
async function main() {
  const args = parseArgs();
  let orderData;
  
  if (args.orderJson) {
    orderData = JSON.parse(args.orderJson);
  } else if (args.orderFile) {
    orderData = JSON.parse(fs.readFileSync(args.orderFile, 'utf8'));
  } else {
    // Demo/test data
    console.log('⚠️ No order data provided, using test data');
    orderData = {
      client: {
        name: 'Test Customer',
        company: 'Test Company Ltd',
        eik: '123456789',
        address: 'Test Street 1, Sofia',
        email: 'test@example.com'
      },
      items: [
        { name: 'CBD Oil 10%', price: 45, quantity: 1 }
      ]
    };
  }
  
  const result = await createInvoice(orderData, {
    sendEmail: args.sendEmail,
    invoiceType: args.invoiceType,
    debug: args.debug
  });
  
  // Output JSON result for scripting
  console.log('\n--- RESULT ---');
  console.log(JSON.stringify(result, null, 2));
  
  process.exit(result.success ? 0 : 1);
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
