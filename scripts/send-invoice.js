#!/usr/bin/env node
/**
 * INV24 Invoice Sender via Playwright
 * Sends an existing invoice via email
 * 
 * Usage: node send-invoice.js --invoice-id 1119419
 * Or:    node send-invoice.js --invoice-number 100000000023
 */

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const CONFIG_PATH = path.join(__dirname, '../data/config.json');

function loadConfig() {
  try {
    if (fs.existsSync(CONFIG_PATH)) {
      return JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
    }
  } catch (e) {}
  return {};
}

function parseArgs() {
  const args = process.argv.slice(2);
  const result = {};
  
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--invoice-id' && args[i + 1]) {
      result.invoiceId = args[++i];
    } else if (args[i] === '--invoice-number' && args[i + 1]) {
      result.invoiceNumber = args[++i];
    } else if (args[i] === '--email' && args[i + 1]) {
      result.email = args[++i];
    } else if (args[i] === '--debug') {
      result.debug = true;
    }
  }
  
  return result;
}

async function sendInvoice(options = {}) {
  const config = loadConfig();
  
  if (!config.inv24_email || !config.inv24_password) {
    throw new Error('INV24 credentials not configured');
  }
  
  console.log('🚀 Starting INV24 invoice send...');
  
  const browser = await chromium.launch({
    headless: !options.debug,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });
  
  const page = await browser.newPage();
  let result = { success: false };
  
  try {
    // Login
    console.log('📝 Logging in...');
    await page.goto('https://www.inv24.com/bg/');
    await page.fill('input[name="userLogin"]', config.inv24_email);
    await page.fill('input[name="userPassword"]', config.inv24_password);
    await page.click('input[name="submit"]');
    await page.waitForURL(/viewManage|invoices/, { timeout: 15000 });
    
    // Find invoice
    if (options.invoiceId) {
      // Direct send by ID
      console.log(`📧 Sending invoice ID ${options.invoiceId}...`);
      await page.goto(`https://www.inv24.com/index.php?lang=bg&class=invoices&action=send&id=${options.invoiceId}`);
      await page.waitForTimeout(2000);
      
      const content = await page.content();
      if (content.includes('успешно') || content.includes('изпратен')) {
        result.success = true;
        console.log('✅ Invoice sent!');
      } else {
        result.error = 'Send may have failed - check INV24';
      }
      
    } else if (options.invoiceNumber) {
      // Find invoice by number first
      console.log(`🔍 Finding invoice #${options.invoiceNumber}...`);
      await page.goto('https://www.inv24.com/index.php?lang=bg&class=invoices&action=viewManage');
      
      // Look for the invoice in the list
      const invoiceRow = await page.$(`text=${options.invoiceNumber}`);
      if (invoiceRow) {
        // Find the send button in that row
        const row = await invoiceRow.evaluateHandle(el => el.closest('tr'));
        const sendBtn = await row.$('img.sendInvImg');
        if (sendBtn) {
          await sendBtn.click();
          await page.waitForTimeout(2000);
          result.success = true;
          console.log('✅ Invoice sent!');
        } else {
          result.error = 'Could not find send button';
        }
      } else {
        result.error = `Invoice ${options.invoiceNumber} not found`;
      }
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    result.error = error.message;
  } finally {
    await browser.close();
  }
  
  console.log('\n--- RESULT ---');
  console.log(JSON.stringify(result, null, 2));
  
  return result;
}

// Main
const args = parseArgs();

if (!args.invoiceId && !args.invoiceNumber) {
  console.log('Usage: node send-invoice.js --invoice-id <id> | --invoice-number <num>');
  process.exit(1);
}

sendInvoice(args).then(result => {
  process.exit(result.success ? 0 : 1);
}).catch(err => {
  console.error('Fatal:', err);
  process.exit(1);
});
