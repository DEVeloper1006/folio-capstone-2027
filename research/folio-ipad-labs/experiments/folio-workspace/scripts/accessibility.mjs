import { chromium } from 'playwright';
import AxeBuilder from '@axe-core/playwright';
import { writeFileSync } from 'node:fs';
const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
const page = await context.newPage();
await page.goto('http://127.0.0.1:5174');
await page.waitForSelector('math-field');
await page.waitForTimeout(500);
const results = await new AxeBuilder({ page })
  .withTags(['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa'])
  .analyze();
writeFileSync('artifacts/accessibility.json', JSON.stringify(results.violations, null, 2));
for (const v of results.violations)
  console.log(
    v.id,
    v.impact,
    v.nodes.map((n) => ({ target: n.target, summary: n.failureSummary })).slice(0, 40),
  );
console.log('Violations:', results.violations.length);
await browser.close();
