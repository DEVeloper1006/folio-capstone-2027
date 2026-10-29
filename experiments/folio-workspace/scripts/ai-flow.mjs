import { chromium } from 'playwright';
import assert from 'node:assert/strict';
const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({ viewport: { width: 1280, height: 1000 } });
const page = await context.newPage();
const requests = [];
await page.route('**/api/health', (r) =>
  r.fulfill({ json: { engine: 'SymPy', ai: true, model: 'test-only' } }),
);
await page.route('**/api/recognize', async (r) => {
  requests.push({ kind: 'recognize', body: r.request().postDataJSON() });
  await r.fulfill({ json: { latex: 'x^2', note: 'Check the exponent.' } });
});
await page.route('**/api/assist', async (r) => {
  requests.push({ kind: 'assist', body: r.request().postDataJSON() });
  await new Promise((resolve) => setTimeout(resolve, 400));
  await r.fulfill({
    json: { text: 'The derivative of x squared is 2x. This is feedback, not an edit.' },
  });
});
const readDoc = () =>
  page.evaluate(() => {
    const w = JSON.parse(localStorage.getItem('folio.workspace.v1'));
    return w.documents.find((d) => d.id === w.activeId);
  });
try {
  await page.goto('http://127.0.0.1:5174');
  await page.waitForSelector('math-field');
  await page.getByRole('button', { name: 'Room to think', exact: true }).click();
  const box = await page.locator('.ink-input').boundingBox();
  await page.mouse.move(box.x + 70, box.y + 40);
  await page.mouse.down();
  await page.mouse.move(box.x + 120, box.y + 100, { steps: 15 });
  await page.mouse.up();
  await page.getByRole('button', { name: 'Convert to math', exact: true }).click();
  assert.equal(
    await page.getByRole('button', { name: 'Recognize selected ink' }).isDisabled(),
    true,
  );
  assert.equal(requests.length, 0);
  await page.getByRole('checkbox').check();
  await page.getByRole('button', { name: 'Recognize selected ink' }).click();
  await page.getByRole('button', { name: 'Accept & insert' }).waitFor();
  assert.equal(requests.length, 1);
  assert.deepEqual(Object.keys(requests[0].body), ['image']);
  assert.ok(requests[0].body.image.startsWith('data:image/png;base64,'));
  await page.locator('dialog math-field').evaluate((el) => {
    el.value = 'x^3';
    el.dispatchEvent(new Event('input', { bubbles: true }));
  });
  await page.getByRole('button', { name: 'Accept & insert' }).click();
  await page.waitForTimeout(500);
  const doc = await readDoc();
  assert.equal(doc.blocks.find((b) => b.type === 'ink').strokes.length, 1);
  assert.equal(doc.blocks.at(-1).content, 'x^3');
  console.log('PASS consent, image-only request, correction, explicit acceptance, preserved ink');

  await page.getByRole('button', { name: 'A second pair of eyes', exact: false }).click();
  assert.equal(await page.getByRole('button', { name: 'Ask Gemini' }).isDisabled(), true);
  await page.getByRole('checkbox').check();
  await page.getByRole('button', { name: 'Ask Gemini' }).click();
  await page.getByRole('button', { name: 'Add feedback as a note' }).waitFor();
  const request = requests.find((r) => r.kind === 'assist');
  assert.equal(request.body.context, 'x^3');
  assert.deepEqual(Object.keys(request.body).sort(), ['context', 'question']);
  assert.equal((await readDoc()).blocks.length, 3);
  await page.getByRole('button', { name: 'Add feedback as a note' }).click();
  await page.waitForTimeout(500);
  assert.equal((await readDoc()).blocks.length, 4);
  assert.equal((await readDoc()).blocks.at(-1).type, 'text');
  console.log('PASS selected-context-only feedback and explicit note acceptance');

  await page.getByRole('button', { name: 'A second pair of eyes', exact: false }).click();
  await page.getByRole('checkbox').check();
  await page.getByRole('button', { name: 'Ask Gemini' }).click();
  await page.getByRole('button', { name: 'Close dialog' }).click();
  await page.getByRole('button', { name: 'A little calculus', exact: true }).click();
  await page.waitForTimeout(700);
  assert.equal(await page.locator('dialog').count(), 0);
  assert.equal((await readDoc()).title, 'A little calculus');
  assert.equal((await readDoc()).blocks.length, 6);
  console.log('PASS late response cannot edit another document or reopen a dialog');
} finally {
  await browser.close();
}
