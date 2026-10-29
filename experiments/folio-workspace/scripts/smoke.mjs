import { chromium } from 'playwright';
import { ComputeEngine } from '@cortex-js/compute-engine';
import { mkdirSync } from 'node:fs';
mkdirSync('artifacts', { recursive: true });
const engine = new ComputeEngine();
for (const latex of [
  String.raw`x^2+2x+1`,
  String.raw`\begin{bmatrix}1&2\\3&4\end{bmatrix}`,
  String.raw`\frac{x}{2}`,
  String.raw`x^2\sin(x)`,
  String.raw`\frac{d}{dx}x^2`,
]) {
  const e = engine.parse(latex);
  console.log('MATHJSON', latex, JSON.stringify(e.json), e.isValid);
}
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({
  viewport: { width: 1440, height: 1050 },
  deviceScaleFactor: 1,
});
page.on('pageerror', (e) => console.error('BROWSER ERROR:', e.message));
page.on('console', (m) => {
  if (m.type() === 'error') console.error('CONSOLE ERROR:', m.text());
});
await page.goto('http://127.0.0.1:5174');
await page.waitForSelector('math-field');
await page.waitForTimeout(1500);
await page.screenshot({ path: 'artifacts/desktop.png', fullPage: true });
console.log('TITLE', await page.title());
console.log('MATHFIELDS', await page.locator('math-field').count());
console.log(
  'HEALTH',
  await page.request.get('http://127.0.0.1:8001/api/health').then((r) => r.json()),
);
await page.getByRole('button', { name: 'Row reduce /rref', exact: false }).click();
await page.getByRole('button', { name: 'Calculate', exact: true }).click();
await page.waitForTimeout(1000);
console.log('COMMAND DIALOG', await page.locator('dialog').innerText());
await page.screenshot({ path: 'artifacts/command.png' });
if (await page.getByRole('button', { name: 'Insert as next step' }).count())
  await page.getByRole('button', { name: 'Insert as next step' }).click();
else await page.getByRole('button', { name: 'Close dialog' }).click();
await page.getByRole('button', { name: 'Export', exact: true }).click();
await page.screenshot({ path: 'artifacts/export.png' });
await page.emulateMedia({ media: 'print' });
await page.pdf({
  path: 'artifacts/sample.pdf',
  format: 'A4',
  printBackground: true,
  preferCSSPageSize: true,
});
console.log('PRINT', await page.locator('.print-document').innerText());
await page.emulateMedia({ media: 'screen' });
await page.getByRole('button', { name: 'Close dialog' }).click();
await page.setViewportSize({ width: 390, height: 844 });
await page.waitForTimeout(400);
await page.screenshot({ path: 'artifacts/mobile.png', fullPage: true });
console.log(
  'WIDTH',
  await page.evaluate(() => ({ width: innerWidth, scroll: document.documentElement.scrollWidth })),
);
await browser.close();
