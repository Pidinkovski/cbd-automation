const { chromium } = require('playwright');

(async () => {
  console.log('🚀 Starting INV24 automation test...');
  
  const browser = await chromium.launch({ 
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });
  
  const page = await browser.newPage();
  
  try {
    // Step 1: Login
    console.log('📝 Logging in...');
    await page.goto('https://www.inv24.com/bg/');
    
    await page.fill('input[name="userLogin"]', 'pakodebeliq@abv.bg');
    await page.fill('input[name="userPassword"]', '268426842aa');
    await page.click('input[name="submit"]');
    
    await page.waitForURL(/viewManage|invoices/, { timeout: 10000 });
    console.log('✅ Logged in! URL:', page.url());
    
    // Step 2: Go to new invoice
    console.log('📝 Creating new invoice...');
    await page.goto('https://www.inv24.com/index.php?lang=bg&class=invoices&action=viewAdd&invoice_type=1');
    await page.waitForLoadState('networkidle');
    
    // Step 3: Fill client info
    console.log('📝 Filling client info...');
    await page.fill('input[name="receiver"]', 'Playwright Test');
    await page.fill('input[name="client_name"]', 'Playwright Company Ltd');
    await page.fill('input[name="client_personal_code"]', '999888777');
    await page.fill('textarea[name="client_address"]', 'Playwright Street 123, Sofia');
    await page.fill('input[name="client_email"]', 'playwright@test.bg');
    
    // Step 4: Add product
    console.log('📝 Adding product...');
    await page.fill('input[name="g_name"]', 'Playwright CBD Oil');
    await page.fill('input[name="g_price"]', '42');
    await page.fill('input[name="g_quantity"]', '1');
    await page.fill('input[name="g_vat"]', '20');
    await page.fill('input[name="g_measurement"]', 'бр');
    
    // Click add product button
    await page.click('input.lisaToote');
    await page.waitForTimeout(1000);
    
    // Step 5: Submit
    console.log('📝 Submitting invoice...');
    await page.click('input[name="save_button"]');
    
    await page.waitForTimeout(3000);
    console.log('📍 Final URL:', page.url());
    
    // Check for success
    const content = await page.content();
    if (content.includes('успешно') || content.includes('viewManage')) {
      console.log('✅ SUCCESS! Invoice created!');
    } else if (page.url().includes('viewAdd')) {
      console.log('❌ Still on form page - submission failed');
    } else {
      console.log('⚠️ Unknown state');
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await browser.close();
  }
})();
