// Resume-after-reload check for the Godot web export (plan criterion 27): in a
// fresh browser profile, clears level 1 with a keyboard route, reloads the page
// and confirms from the console log that the game resumed at level 2.
// Usage: node tools/resume_web.mjs [buildDir]   (default: build/web)
// Env:   RESUME_BOOT_TIMEOUT_MS (default 30000), RESUME_CLEAR_TIMEOUT_MS (default 25000),
//        RESUME_FLUSH_MS (default 1500)
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { launchChrome, serveBuild } from './web_util.mjs';

const repoRoot = resolve(fileURLToPath(import.meta.url), '..', '..');
const buildDir = resolve(process.argv[2] ?? join(repoRoot, 'build', 'web'));
const bootTimeoutMs = Number(process.env.RESUME_BOOT_TIMEOUT_MS ?? 30000);
const clearTimeoutMs = Number(process.env.RESUME_CLEAR_TIMEOUT_MS ?? 25000);
// Godot writes user:// to IndexedDB asynchronously and reports no completion, so
// the check waits this long after the save before reloading. Raise it on slow machines.
const flushMs = Number(process.env.RESUME_FLUSH_MS ?? 1500);

// Level 1 solved with the arrow keys only, anchored on the room walls so small
// timing jitter does not matter: up to the top wall, right to the right wall,
// then down beside the bed. [keys held, milliseconds]
const LEVEL_1_KEYS = [[['ArrowUp'], 1800], [['ArrowRight'], 4000], [['ArrowDown'], 1600]];

const failures = [];
const log = [];
let browser;
let server;

// Resolves once a console line matching `pattern` has been logged (including earlier ones).
function logged(pattern, timeoutMs, what) {
  const started = Date.now();
  return new Promise((ok, fail) => {
    const poll = setInterval(() => {
      const line = log.find((l) => pattern.test(l));
      if (line !== undefined) {
        clearInterval(poll);
        ok(line);
      } else if (Date.now() - started > timeoutMs) {
        clearInterval(poll);
        fail(new Error(`timed out after ${timeoutMs} ms waiting for ${what}`));
      }
    }, 50);
  });
}

try {
  const served = await serveBuild(buildDir);
  server = served.server;
  browser = await launchChrome();
  // A new context has empty IndexedDB, so the game starts without a save.
  const context = await browser.newContext({ viewport: { width: 1280, height: 720 } });
  const page = await context.newPage();
  page.on('pageerror', (e) => failures.push(`page error: ${e.message}`));
  page.on('console', (m) => {
    log.push(m.text());
    if (m.type() === 'error') failures.push(`console error: ${m.text()}`);
  });

  await page.goto(served.url, { timeout: bootTimeoutMs });
  await logged(/^\[Game\] Loading level 1\/\d+/, bootTimeoutMs, 'level 1 to load');
  // Keyboard events go to the focused canvas; focusing is not game input.
  await page.focus('canvas');
  await page.waitForTimeout(500);
  for (const [keys, ms] of LEVEL_1_KEYS) {
    for (const key of keys) await page.keyboard.down(key);
    await page.waitForTimeout(ms);
    for (const key of keys) await page.keyboard.up(key);
  }
  await logged(/^\[Game\] Level 1 cleared/, clearTimeoutMs, 'level 1 to be cleared');
  await logged(/^\[Game\] Saved progress .*furthest level 2/, 5000, 'the save after clearing level 1');
  await logged(/^\[Game\] Loading level 2\/\d+/, 10000, 'level 2 to load after the clear');
  await page.waitForTimeout(flushMs);

  log.length = 0;
  await page.reload({ timeout: bootTimeoutMs });
  await logged(/^\[Game\] Loaded save from user:\/\/progress\.json: furthest level 2/, bootTimeoutMs, 'the save to load after reload');
  await logged(/^\[Game\] Loading level 2\/\d+/, bootTimeoutMs, 'the game to resume at level 2');
  if (log.some((l) => /^\[Game\] Loading level 1\//.test(l))) failures.push('after reload the game loaded level 1, not level 2');
} catch (err) {
  failures.push(`resume check aborted: ${err.message}`);
} finally {
  await browser?.close();
  server?.close();
}

if (failures.length > 0) {
  for (const f of failures) console.error(`FAIL ${f}`);
  console.error('--- console log ---\n' + log.join('\n'));
  process.exit(1);
}
console.log(`PASS resume after reload (${buildDir})`);
