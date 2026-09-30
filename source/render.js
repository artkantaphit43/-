// Render an HTML file to PDF with headless Chromium (Playwright).
// usage: node render.js input.html output.pdf
let playwright;
try { playwright = require('playwright'); } catch (e) { playwright = require('/opt/node22/lib/node_modules/playwright'); }
const path = require('path');
(async () => {
  const [, , inp, out] = process.argv;
  const browser = await playwright.chromium.launch();
  const page = await browser.newPage();
  await page.goto('file://' + path.resolve(inp), { waitUntil: 'networkidle' });
  await page.evaluate(() => document.fonts.ready);
  await page.pdf({ path: out, format: 'A4', printBackground: true, preferCSSPageSize: true, outline: true, tagged: true });
  await browser.close();
})();
