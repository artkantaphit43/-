// Render index.html to an A4 portrait PDF with headless Chromium.
// Usage: node pe-flow/build.mjs [output-dir]   (default: repo root)
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

const require = createRequire(import.meta.url);
let playwright;
try { playwright = require('playwright'); }
catch { playwright = require('/opt/node22/lib/node_modules/playwright'); }

const here = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.resolve(process.argv[2] || path.join(here, '..'));
const targets = [
  ['index.html', 'PE-Project-Control-Flow.pdf'],
  ['summary.html', 'PE-Project-Control-Flow-1page.pdf'],
];

const browser = await playwright.chromium.launch();
for (const [src, pdf] of targets) {
  const page = await browser.newPage();
  await page.emulateMedia({ media: 'print' });
  page.on('console', m => console.log('[page]', m.text()));
  await page.goto(pathToFileURL(path.join(here, src)).href);
  await page.waitForFunction(() => window.__done === true);
  const report = await page.evaluate(() => window.__overflow);
  for (const r of report) console.log(`${src} page ${r.page}: overflow ${r.overflowPx}px, spare ${r.spareMm}mm`);
  const out = path.join(outDir, pdf);
  await page.pdf({ path: out, format: 'A4', printBackground: true, preferCSSPageSize: true });
  await page.close();
  console.log('wrote', out);
}
await browser.close();
