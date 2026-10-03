// Smoke test for the Godot web export: serves the build locally, loads it in
// headless Chrome and fails on any failed request, page error, console error,
// missing engine boot log or a still-visible Godot status overlay.
// Usage: node tools/smoke_web.mjs [buildDir]   (default: build/web)
// Env:   SMOKE_BOOT_TIMEOUT_MS (default 30000), SMOKE_SETTLE_MS (default 3000)
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const repoRoot = resolve(fileURLToPath(import.meta.url), '..', '..');
const buildDir = resolve(process.argv[2] ?? join(repoRoot, 'build', 'web'));
const bootTimeoutMs = Number(process.env.SMOKE_BOOT_TIMEOUT_MS ?? 30000);
const settleMs = Number(process.env.SMOKE_SETTLE_MS ?? 3000);
const screenshotPath = join(buildDir, '..', 'smoke.png');

const MIME = {
  '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream', '.png': 'image/png', '.svg': 'image/svg+xml',
};

const server = createServer(async (req, res) => {
  const path = resolve(buildDir, '.' + decodeURIComponent(new URL(req.url, 'http://localhost').pathname));
  if (path !== buildDir && !path.startsWith(buildDir + sep)) {
    res.writeHead(403).end();
    return;
  }
  try {
    const body = await readFile(path);
    res.writeHead(200, { 'Content-Type': MIME[extname(path)] ?? 'application/octet-stream' }).end(body);
  } catch (err) {
    console.error(`[server] ${req.url}: ${err.code ?? err.message}`);
    res.writeHead(404).end();
  }
});

const failures = [];
let browser;
try {
  await new Promise((ok, fail) => server.once('error', fail).listen(0, '127.0.0.1', ok));
  const url = `http://127.0.0.1:${server.address().port}/index.html`;
  browser = await chromium.launch({
    channel: 'chrome',
    headless: true,
    args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
  });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  page.on('pageerror', (e) => failures.push(`page error: ${e.message}`));
  page.on('requestfailed', (r) => failures.push(`request failed: ${r.url()} ${r.failure()?.errorText}`));
  page.on('response', (r) => { if (r.status() >= 400) failures.push(`HTTP ${r.status()}: ${r.url()}`); });
  page.on('console', (m) => {
    // SwiftShader emits GPU performance warnings; only real errors fail the test.
    if (m.type() === 'error') failures.push(`console error: ${m.text()}`);
  });
  // Settled to a value up front so it can never become an unhandled rejection if goto throws.
  const booted = page.waitForEvent('console', {
    predicate: (m) => m.text().startsWith('Godot Engine v'),
    timeout: bootTimeoutMs,
  }).then(() => null, (err) => err);
  await page.goto(url, { timeout: bootTimeoutMs });
  const bootError = await booted;
  if (bootError !== null) throw new Error(`engine did not boot: ${bootError.message.split('\n')[0]}`);
  await page.waitForTimeout(settleMs);
  const overlayVisible = await page.evaluate(() => {
    const status = document.getElementById('status');
    return status !== null && getComputedStyle(status).display !== 'none' && getComputedStyle(status).visibility !== 'hidden';
  });
  if (overlayVisible) failures.push('Godot status overlay still visible (engine failed to start)');
  if ((await page.locator('canvas').count()) === 0) failures.push('no canvas element');
  const png = await page.screenshot({ path: screenshotPath });
  console.log(`screenshot: ${screenshotPath}`);
  // A booted engine that draws nothing leaves one flat colour; count distinct colours in the screenshot.
  const distinctColors = await page.evaluate(async (b64) => {
    const img = new Image();
    img.src = `data:image/png;base64,${b64}`;
    await img.decode();
    const canvas = document.createElement('canvas');
    canvas.width = img.width;
    canvas.height = img.height;
    const ctx = canvas.getContext('2d');
    ctx.drawImage(img, 0, 0);
    const data = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
    const colors = new Set();
    for (let i = 0; i < data.length && colors.size < 16; i += 4) {
      colors.add((data[i] << 16) | (data[i + 1] << 8) | data[i + 2]);
    }
    return colors.size;
  }, png.toString('base64'));
  if (distinctColors < 2) failures.push('screenshot is a single flat colour (nothing rendered)');
} catch (err) {
  failures.push(`smoke test aborted: ${err.message}`);
} finally {
  await browser?.close();
  server.close();
}

if (failures.length > 0) {
  for (const f of failures) console.error(`FAIL ${f}`);
  process.exit(1);
}
console.log(`PASS ${buildDir}`);
