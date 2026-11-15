import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import { readFileSync, mkdirSync } from 'node:fs';
mkdirSync('artifacts', { recursive: true });
const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({
  viewport: { width: 1440, height: 1000 },
  acceptDownloads: true,
});
const page = await context.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
const pause = () => page.waitForTimeout(500);
const workspace = () => page.evaluate(() => JSON.parse(localStorage.getItem('folio.workspace.v1')));
const current = async () => {
  const w = await workspace();
  return w.documents.find((d) => d.id === w.activeId);
};
const setMath = async (latex, locator = page.locator('.editor-block.is-selected math-field')) => {
  await locator.evaluate((el, latex) => {
    el.value = latex;
    el.dispatchEvent(new Event('input', { bubbles: true }));
  }, latex);
  await pause();
};
const palette = async (name) => {
  await page.getByRole('button', { name: 'Find a command' }).click();
  await page.getByRole('button', { name, exact: false }).last().click();
};
try {
  await page.goto('http://127.0.0.1:5174');
  await page.waitForSelector('math-field');
  await pause();
  await page.getByRole('button', { name: 'New document', exact: true }).first().click();
  await page
    .getByRole('textbox', { name: 'Document title', exact: true })
    .fill('Integration test notebook');
  await setMath(String.raw`x^2+2x+1`);
  assert.equal((await current()).blocks[0].content, String.raw`x^2+2x+1`);
  console.log('PASS create, title, expression editing');

  await page.keyboard.press('Meta+Shift+d');
  await pause();
  assert.equal((await current()).blocks.length, 2);
  await setMath('x^3');
  assert.equal((await current()).blocks[0].content, String.raw`x^2+2x+1`);
  console.log('PASS independent step duplication');

  await page.getByRole('button', { name: 'Differentiate /derivative' }).click();
  await page.getByRole('button', { name: 'Calculate', exact: true }).click();
  await page.getByRole('button', { name: 'Insert as next step' }).waitFor();
  await page.getByRole('button', { name: 'Insert as next step' }).click();
  await pause();
  assert.match((await current()).blocks[2].content, /3.*x.*2/);
  await page.getByRole('button', { name: 'Undo', exact: true }).click();
  await pause();
  assert.equal((await current()).blocks.length, 2);
  await page.getByRole('button', { name: 'Redo', exact: true }).click();
  await pause();
  assert.equal((await current()).blocks.length, 3);
  console.log('PASS symbolic calculation, acceptance, undo, redo');

  await page.getByRole('button', { name: 'Text', exact: true }).click();
  await page
    .getByRole('textbox', { name: 'Text step 4' })
    .fill('This note should not appear in exported work.');
  await pause();
  await page.getByRole('button', { name: 'Exclude step 4 from export' }).click();
  await pause();
  await page.getByRole('button', { name: 'Export', exact: true }).click();
  assert.equal(
    await page
      .locator('.export-preview')
      .getByText('This note should not appear in exported work.')
      .count(),
    0,
  );
  const downloadPromise = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Download .folio', exact: true }).click();
  const dl = await downloadPromise;
  await dl.saveAs('artifacts/test-notebook.folio');
  const exported = JSON.parse(readFileSync('artifacts/test-notebook.folio', 'utf8'));
  assert.equal(exported.document.blocks[3].included, false);
  await page.getByRole('button', { name: 'Close dialog' }).click();
  await page.reload();
  await page.waitForSelector('math-field');
  await pause();
  assert.equal((await current()).title, 'Integration test notebook');
  assert.equal((await current()).blocks.length, 4);
  console.log('PASS exclusion, portable backup, autosave/reopen');

  await page.getByRole('button', { name: 'Ink', exact: true }).click();
  await pause();
  const canvas = page.locator('.ink-input');
  const box = await canvas.boundingBox();
  assert.ok(box);
  for (let offset of [0, 100]) {
    await page.mouse.move(box.x + 40 + offset, box.y + 40);
    await page.mouse.down();
    await page.mouse.move(box.x + 80 + offset, box.y + 100, { steps: 20 });
    await page.mouse.up();
  }
  await pause();
  assert.equal((await current()).blocks.find((b) => b.type === 'ink').strokes.length, 2);
  await page.getByRole('button', { name: 'Select handwriting', exact: true }).click();
  await page.mouse.move(box.x + 30, box.y + 30);
  await page.mouse.down();
  await page.mouse.move(box.x + 95, box.y + 115, { steps: 8 });
  await page.mouse.up();
  await page.getByRole('button', { name: 'Duplicate selected ink', exact: true }).click();
  await pause();
  assert.equal((await current()).blocks.find((b) => b.type === 'ink').strokes.length, 3);
  await page.getByRole('button', { name: 'Delete selected ink', exact: true }).click();
  await pause();
  assert.equal((await current()).blocks.find((b) => b.type === 'ink').strokes.length, 2);
  await page.getByRole('button', { name: 'Undo', exact: true }).click();
  await pause();
  assert.equal((await current()).blocks.find((b) => b.type === 'ink').strokes.length, 3);
  console.log('PASS drawing, region selection, duplicate, delete, undo');

  await page.getByRole('button', { name: /Convert/ }).click();
  assert.equal(
    await page.getByRole('button', { name: 'Recognize selected ink' }).isDisabled(),
    true,
  );
  await page.getByRole('button', { name: 'Enter the expression manually' }).click();
  await setMath('x^2', page.locator('dialog math-field'));
  await page.getByRole('button', { name: 'Accept & insert' }).click();
  await pause();
  assert.equal((await current()).blocks.find((b) => b.type === 'ink').strokes.length, 3);
  assert.equal((await current()).blocks.at(-1).content, 'x^2');
  console.log('PASS honest disconnected AI state, manual correction, original ink preservation');

  await page.locator('input[type=file]').setInputFiles('artifacts/test-notebook.folio');
  await pause();
  const afterImport = await workspace();
  assert.equal(
    afterImport.documents.filter((d) => d.title === 'Integration test notebook').length,
    2,
  );
  assert.equal((await current()).blocks.length, 4);
  assert.notEqual((await current()).id, exported.document.id);
  console.log('PASS file import as independent copy');

  await page.getByRole('button', { name: 'Create alternative document', exact: true }).click();
  await pause();
  assert.match((await current()).title, /alternative/);
  await page.getByRole('textbox', { name: 'Document title', exact: true }).fill('Alternative path');
  await pause();
  assert.equal(
    (await workspace()).documents.filter((d) => d.title === 'Integration test notebook').length,
    2,
  );
  console.log('PASS alternative document branch');

  await page.setViewportSize({ width: 390, height: 844 });
  await pause();
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth), 390);
  assert.ok((await page.locator('.sidebar').boundingBox()).x < 0);
  await page.getByRole('button', { name: 'Open navigation' }).click();
  await pause();
  await page.getByRole('button', { name: 'Room to think', exact: true }).click();
  await pause();
  assert.equal((await current()).title, 'Room to think');
  await page.screenshot({ path: 'artifacts/mobile-ink.png', fullPage: true });
  console.log('PASS mobile layout and navigation');
  assert.deepEqual(errors, []);
  console.log('PASS no uncaught browser errors');
} finally {
  await browser.close();
}
