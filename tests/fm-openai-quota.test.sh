#!/usr/bin/env bash
# Quota parser, bounded subprocess, status coexistence, and installed Pi SDK lifecycle.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PI_PACKAGE_DIR=${FM_PI_PACKAGE_DIR:-"$(npm root -g)/@earendil-works/pi-coding-agent"}
if [ ! -f "$PI_PACKAGE_DIR/package.json" ]; then
  echo "skip: installed Pi SDK not found"
  exit 0
fi
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-openai-quota.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
export EXT="$ROOT/.pi/extensions/fm-openai-quota.ts" PI_PACKAGE_DIR TMP_ROOT
node --input-type=module <<'JS'
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { stripVTControlCharacters } from 'node:util';
import { setTimeout as sleep } from 'node:timers/promises';
import { mock } from 'node:test';
import childProcess from 'node:child_process';
import { syncBuiltinESMExports } from 'node:module';
const { parseQuota, startQuotaStatus } = await import(pathToFileURL(process.env.EXT));
const now = Date.now();
const fixture = () => ({ schemaVersion: 3, providers: [{ provider: 'codex',
  state: { status: 'fresh', stale: false, refreshedAt: new Date(now).toISOString() },
  windows: [{ id: 'weekly', label: 'week', percentRemaining: 12.3, resetsAt: new Date(now + 86400000).toISOString() }],
}] });
const parse = (data) => parseQuota(JSON.stringify(data), now);
assert.equal(parse(fixture()).text, 'OpenAI week 12.3% left');
let data = fixture();
data.providers[0].windows.push({ label: '5h', percentRemaining: 0 });
assert.equal(parse(data).text, 'OpenAI week 12.3% left · 5h 0% left');
for (const change of [
  d => d.schemaVersion = 2,
  d => d.providers = [],
  d => d.providers.push(d.providers[0]),
  d => d.providers[0].provider = 'claude',
  d => d.providers[0].state.status = 'error',
  d => delete d.providers[0].state.stale,
  d => d.providers[0].state.refreshedAt = 'invalid',
  d => d.providers[0].state.refreshedAt = new Date(now + 60000).toISOString(),
  d => d.providers[0].windows = [],
  d => d.providers[0].windows[0].percentRemaining = '0',
  d => d.providers[0].windows[0].percentRemaining = null,
  d => d.providers[0].windows[0].percentRemaining = 101,
  d => d.providers[0].windows[0].percentRemaining = -1,
  d => d.providers[0].windows[0].label = '\x1b[31msecret',
  d => d.providers[0].windows[0].resetsAt = 'invalid',
]) { data = fixture(); change(data); assert.throws(() => parse(data), /unknown/); }
for (const change of [
  d => d.providers[0].state.stale = true,
  d => d.providers[0].state.refreshedAt = new Date(now - 300000).toISOString(),
  d => d.providers[0].windows[0].resetsAt = new Date(now).toISOString(),
]) { data = fixture(); change(data); assert.throws(() => parse(data), /stale/); }
assert.throws(() => parseQuota('not json'));
if (process.env.FM_QUOTA_SNAPSHOT) {
  // Private, opt-in real output. Never print the account snapshot or its percentage.
  const snapshot = parseQuota(readFileSync(process.env.FM_QUOTA_SNAPSHOT, 'utf8'));
  assert.match(snapshot.text, /^OpenAI .+% left/);
  console.log('ok - fresh real quota-axi output parsed');
}
console.log('ok - only actual valid windows, explicit stale/unknown, safe terminal text');

// Control time and subprocess completion, not SDK internals.
const originalExec = childProcess.execFile;
let calls = [];
childProcess.execFile = (command, args, options, callback) => {
  assert.equal(command, 'quota-axi');
  assert.deepEqual(args, ['--provider', 'codex', '--json']);
  assert.equal(options.timeout, 5000);
  assert.equal(options.killSignal, 'SIGKILL');
  assert.equal(options.maxBuffer, 256 * 1024);
  calls.push({ options, callback });
};
syncBuiltinESMExports();
mock.timers.enable({ apis: ['Date', 'setTimeout'], now });
const statuses = new Map([['other-extension', 'unchanged']]);
const ui = { setStatus(key, value) { value === undefined ? statuses.delete(key) : statuses.set(key, value); } };
const key = 'firstmate-openai-quota';
let stop = startQuotaStatus({ ui });
assert.equal(statuses.get(key), 'OpenAI quota unknown');
mock.timers.tick(120000);
assert.equal(calls.length, 1, 'no overlapping refresh while pending');
calls[0].callback(null, JSON.stringify(fixture()));
assert.match(statuses.get(key), /week 12.3% left/);
mock.timers.tick(60000);
assert.equal(calls.length, 2);
mock.timers.tick(120000);
assert.equal(statuses.get(key), 'OpenAI quota stale', 'cached success expires even during pending refresh');
calls[1].callback(new Error('private error secret'), '');
assert.equal(statuses.get(key), 'OpenAI quota unavailable');
mock.timers.tick(60000);
const pending = calls.at(-1);
stop(); stop();
assert.equal(pending.options.signal.aborted, true);
pending.callback(null, JSON.stringify(fixture()));
mock.timers.tick(600000);
assert.equal(calls.length, 3);
assert.deepEqual([...statuses], [['other-extension', 'unchanged']]);
mock.timers.reset();
childProcess.execFile = originalExec;
syncBuiltinESMExports();
console.log('ok - cache expiry, no overlap, failures, cancellation, late callback and timer cleanup');

// Real child processes test ENOENT, nonzero exit, malformed JSON, output cap,
// deadline, and shutdown kill. The fake CLI never reads account credentials.
const originalPath = process.env.PATH;
const bin = `${process.env.TMP_ROOT}/bin`;
mkdirSync(bin);
process.env.PATH = bin;
async function waitFor(predicate, timeout = 7000) {
  const deadline = Date.now() + timeout;
  while (!predicate()) {
    assert.ok(Date.now() < deadline, 'deadline waiting for status');
    await sleep(20);
  }
}
function cli(body) {
  writeFileSync(`${bin}/quota-axi`, `#!${process.execPath}\n${body}\n`, { mode: 0o700 });
}
async function unavailable(body) {
  if (body) cli(body);
  const stop = startQuotaStatus({ ui });
  try { await waitFor(() => statuses.get(key) === 'OpenAI quota unavailable'); }
  finally { stop(); }
}
await unavailable();
await unavailable('process.stderr.write("secret"); process.exit(1)');
await unavailable('console.log("bad json")');
await unavailable('process.stdout.write("x".repeat(300000))');
await unavailable('process.on("SIGTERM", () => {}); setInterval(() => {}, 1000)');
const pidFile = `${process.env.TMP_ROOT}/pid`;
cli(`require('node:fs').writeFileSync(${JSON.stringify(pidFile)}, String(process.pid)); setInterval(() => {}, 1000)`);
stop = startQuotaStatus({ ui });
await waitFor(() => { try { return !!readFileSync(pidFile); } catch { return false; } });
const pid = Number(readFileSync(pidFile, 'utf8'));
stop();
await waitFor(() => { try { process.kill(pid, 0); return false; } catch { return true; } });
assert.equal(statuses.has(key), false);
console.log('ok - real child missing/failing/malformed/oversized/timeout and shutdown cleanup');

// Load the actual extension with Pi's loader and dispatch lifecycle via AgentSession.
const sdk = await import(pathToFileURL(`${process.env.PI_PACKAGE_DIR}/dist/index.js`));
const { InMemoryCredentialStore } = await import(pathToFileURL(`${process.env.PI_PACKAGE_DIR}/node_modules/@earendil-works/pi-ai/dist/index.js`));
const settingsManager = sdk.SettingsManager.inMemory();
const loader = new sdk.DefaultResourceLoader({ cwd: process.env.TMP_ROOT, agentDir: process.env.TMP_ROOT,
  settingsManager, noExtensions: true, additionalExtensionPaths: [process.env.EXT],
  noSkills: true, noPromptTemplates: true, noThemes: true, noContextFiles: true });
await loader.reload();
assert.deepEqual(loader.getExtensions().errors, []);
const modelRuntime = await sdk.ModelRuntime.create({ credentials: new InMemoryCredentialStore(),
  modelsPath: `${process.env.TMP_ROOT}/models.json`, modelsStorePath: `${process.env.TMP_ROOT}/models-store.json`, allowModelNetwork: false });
const model = { id: 'gpt-6-astra', name: 'test only - no calls', provider: 'openai-codex',
  api: 'openai-codex-responses', baseUrl: 'https://invalid.invalid', reasoning: true,
  input: ['text'], contextWindow: 272000, maxTokens: 128000,
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } };
const { session } = await sdk.createAgentSession({ cwd: process.env.TMP_ROOT, agentDir: process.env.TMP_ROOT,
  resourceLoader: loader, modelRuntime, model, thinkingLevel: 'medium', settingsManager,
  sessionManager: sdk.SessionManager.inMemory(process.env.TMP_ROOT), noTools: 'all' });
const { FooterComponent } = await import(pathToFileURL(`${process.env.PI_PACKAGE_DIR}/dist/modes/interactive/components/footer.js`));
const { initTheme } = await import(pathToFileURL(`${process.env.PI_PACKAGE_DIR}/dist/modes/interactive/theme/theme.js`));
const { visibleWidth } = await import(pathToFileURL(`${process.env.PI_PACKAGE_DIR}/node_modules/@earendil-works/pi-tui/dist/index.js`));
initTheme('dark', false);
const footer = new FooterComponent(session, { getGitBranch: () => null,
  getAvailableProviderCount: () => 1, getExtensionStatuses: () => statuses });
const baseline = footer.render(160);
// Optional visual evidence from the installed native footer, using synthetic quota only.
function capture(name, width = 160) {
  if (!process.env.FM_QUOTA_RENDER_DIR) return;
  mkdirSync(process.env.FM_QUOTA_RENDER_DIR, { recursive: true });
  const lines = footer.render(width).map(stripVTControlCharacters);
  const escape = text => text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  const rows = lines.map((line, i) => `<text x="16" y="${28 + i * 24}" xml:space="preserve">${escape(line)}</text>`).join('');
  writeFileSync(`${process.env.FM_QUOTA_RENDER_DIR}/${name}-${width}.svg`,
    `<svg xmlns="http://www.w3.org/2000/svg" width="${width * 10 + 32}" height="${lines.length * 24 + 24}"><rect width="100%" height="100%" fill="#181818"/><g fill="#aaaaaa" font-family="monospace" font-size="16">${rows}</g></svg>`);
}
capture('disabled');
const errors = [];
await session.bindExtensions({ uiContext: ui, mode: 'tui', onError: e => errors.push(e) });
assert.equal(statuses.has(key), false, 'optional flag off starts nothing');
session.extensionRunner.setFlagValue('openai-quota', true);
await session.bindExtensions({ mode: 'print' });
assert.equal(statuses.has(key), false, 'noninteractive mode starts nothing');
cli(`console.log(JSON.stringify(${JSON.stringify(fixture())}))`);
session.extensionRunner.setUIContext(ui, 'tui');
for (const reason of ['startup', 'reload', 'new', 'resume', 'fork']) {
  await session.extensionRunner.emit({ type: 'session_start', reason });
  if (reason === 'startup') capture('loading');
  await waitFor(() => statuses.get(key)?.includes('week 12.3% left'));
  if (reason === 'startup') for (const width of [40, 80, 160]) capture('fresh', width);
  const rendered = footer.render(160);
  assert.deepEqual(rendered.slice(0, -1), baseline.slice(0, -1), 'native model/effort/context footer untouched');
  assert.match(rendered.join('\n'), /gpt-6-astra/);
  assert.match(rendered.join('\n'), /medium/);
  assert.match(rendered.join('\n'), /OpenAI week 12.3% left/);
  for (const width of [20, 40, 80, 160]) {
    assert.ok(footer.render(width).every(line => visibleWidth(line) <= width), 'native narrow rendering');
  }
  await session.extensionRunner.emit({ type: 'session_shutdown', reason: reason === 'startup' ? 'quit' : reason });
  assert.equal(statuses.has(key), false);
}
capture('shutdown');
for (const [name, body, expected] of [
  ['stale', `console.log(JSON.stringify(${JSON.stringify({ ...fixture(), providers: [{ ...fixture().providers[0], state: { status: 'stale', stale: true } }] })}))`, 'OpenAI quota stale'],
  ['unavailable', 'process.exit(1)', 'OpenAI quota unavailable'],
]) {
  cli(body);
  await session.extensionRunner.emit({ type: 'session_start', reason: 'startup' });
  await waitFor(() => statuses.get(key) === expected);
  assert.match(footer.render(160).join('\n'), new RegExp(expected));
  capture(name);
  await session.extensionRunner.emit({ type: 'session_shutdown', reason: 'quit' });
  assert.equal(statuses.has(key), false);
}
assert.deepEqual(errors, []);
assert.equal(statuses.get('other-extension'), 'unchanged');
session.dispose();
process.env.PATH = originalPath;
console.log('ok - installed Pi SDK loading, opt-in, mode guard, lifecycle and status coexistence (no model calls)');
JS
