import { chromium } from 'playwright';
import assert from 'node:assert/strict';
const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
const page = await context.newPage();
try {
  await page.goto('http://127.0.0.1:5174');
  await page.waitForSelector('math-field');
  await page.getByRole('button', { name: 'Find a command' }).click();
  await page.getByRole('textbox', { name: 'Search commands' }).fill('row operation');
  await page.getByRole('button', { name: /Matrix row operation/ }).click();
  await page.locator('dialog math-field').evaluate((el) => {
    el.value = '-2';
    el.dispatchEvent(new Event('input', { bubbles: true }));
  });
  await page.getByRole('button', { name: 'Calculate', exact: true }).click();
  await page.getByRole('button', { name: 'Insert as next step' }).waitFor();
  assert.match(await page.locator('.result-panel').innerText(), /R2 <- R2 \+ \(-2\) R1/);
  await page.getByRole('button', { name: 'Insert as next step' }).click();
  await page.waitForTimeout(500);
  const row = await page.evaluate(() => {
    const w = JSON.parse(localStorage.getItem('folio.workspace.v1'));
    return w.documents[0].blocks[5];
  });
  assert.match(row.content, /0 & -3 & 3 & 0/);
  assert.match(row.note, /R2 <-/);
  console.log('PASS explicit row operation, correct result, recorded operation');

  await page.getByRole('button', { name: 'New document', exact: true }).first().click();
  await page.waitForTimeout(120);
  const mf = page.locator('.editor-block.is-selected math-field');
  await mf.click();
  await page.waitForTimeout(100);
  await page.keyboard.type('x^2', { delay: 30 });
  await page.keyboard.press('ArrowRight');
  await page.keyboard.type('+2x+1', { delay: 30 });
  const latex = await mf.evaluate((el) => el.value);
  assert.match(latex, /x\^2/);
  assert.match(latex, /2x/);
  assert.match(latex, /\+1/);
  await page.keyboard.press('Enter');
  await page.waitForTimeout(150);
  assert.equal(await page.locator('.editor-block math-field').count(), 2);
  console.log('PASS actual keyboard math entry and Enter to add a step');
  await page.locator('.editor-block.is-selected math-field').click();
  await page.waitForTimeout(100);
  await page.keyboard.type('/');
  await page.waitForTimeout(100);
  assert.equal(await page.locator('dialog').count(), 1);
  await page.keyboard.press('Escape');
  console.log('PASS slash opens commands from an empty expression');

  await page.getByRole('button', { name: 'Text', exact: true }).click();
  await page.getByRole('button', { name: 'Insert fraction', exact: true }).click();
  await page.waitForTimeout(200);
  const fraction = await page
    .locator('.editor-block.is-selected math-field')
    .evaluate((el) => el.value);
  assert.match(fraction, /\\frac/);
  assert.doesNotMatch(fraction, /#0/);
  console.log('PASS math templates create a structured field from a text selection');

  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForTimeout(300);
  const commandButton = page.getByRole('button', { name: 'Commands', exact: true });
  const bounds = await commandButton.boundingBox();
  assert.ok(bounds.x >= 0 && bounds.x + bounds.width <= 390);
  await commandButton.click();
  assert.equal(await page.getByRole('textbox', { name: 'Search commands' }).isVisible(), true);
  await page.keyboard.press('Escape');
  assert.equal(await page.locator('dialog').count(), 0);
  console.log('PASS mobile command button is visible and keyboard dialog closes');
} finally {
  await browser.close();
}
