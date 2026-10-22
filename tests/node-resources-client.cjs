// Disposable Linux QEMU client: measure the entire real TypeScript family.
// Its supervisor sees procfs, moves our stopped child to a pids cgroup, then
// resumes it. This client and its workspace never touch host/user projects.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { pathToFileURL } = require('node:url');

const workspace = process.env.VIM_QEMU_GOPLS_WORKSPACE || '/home/tester/resource-typescript';
const launcher = '/opt/vim-config/bin/language-server';
const uri = file => pathToFileURL(file).href;

class Client {
  constructor(env) {
    this.buffer = Buffer.alloc(0);
    this.errors = '';
    this.pending = new Map();
    this.nextId = 1;
    this.closed = false;
    this.child = spawn('/bin/sh', ['-c', 'kill -STOP "$$"; exec "$@"',
      'resource-fixture', launcher, 'typescript'],
    { cwd: workspace, env, stdio: ['pipe', 'pipe', 'pipe'] });
    console.log(`GOPLS_RESOURCE_CHILD_PID=${this.child.pid}`);
    this.child.stdin.on('error', () => {});
    this.child.stdout.on('data', chunk => this.output(chunk));
    this.child.stderr.on('data', chunk => { this.errors = (this.errors + chunk).slice(0, 16384); });
    this.exited = new Promise(resolve => {
      this.child.once('error', error => { this.errors += String(error); });
      this.child.once('close', (code, signal) => {
        this.closed = true;
        this.exit = { code, signal };
        for (const item of this.pending.values()) {
          clearTimeout(item.timer);
          item.reject(new Error(`TypeScript closed: code=${code}, signal=${signal}; ${this.errors}`));
        }
        this.pending.clear();
        resolve(this.exit);
      });
    });
  }
  send(message) {
    const body = Buffer.from(JSON.stringify({ jsonrpc: '2.0', ...message }));
    this.child.stdin.write(Buffer.concat([Buffer.from(`Content-Length: ${body.length}\r\n\r\n`), body]));
  }
  output(chunk) {
    this.buffer = Buffer.concat([this.buffer, chunk]);
    while (true) {
      const end = this.buffer.indexOf('\r\n\r\n');
      if (end < 0) return;
      const match = /^Content-Length:\s*(\d+)\s*$/im.exec(this.buffer.subarray(0, end).toString());
      assert.ok(match, 'LSP framing');
      const length = Number(match[1]);
      if (this.buffer.length < end + 4 + length) return;
      const message = JSON.parse(this.buffer.subarray(end + 4, end + 4 + length).toString());
      this.buffer = this.buffer.subarray(end + 4 + length);
      if (message.method && Object.hasOwn(message, 'id')) {
        let result = null;
        if (message.method === 'workspace/configuration') result = (message.params?.items || []).map(() => ({}));
        if (message.method === 'workspace/workspaceFolders') result = [{ uri: uri(workspace), name: 'fixture' }];
        if (message.method === 'workspace/applyEdit') result = { applied: false };
        this.send({ id: message.id, result });
      } else if (Object.hasOwn(message, 'id')) {
        const item = this.pending.get(message.id);
        if (!item) continue;
        clearTimeout(item.timer);
        this.pending.delete(message.id);
        if (message.error) item.reject(new Error(JSON.stringify(message.error)));
        else item.resolve(message.result);
      }
    }
  }
  request(method, params, timeout = 90000) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`Timeout: ${method}; ${this.errors}`));
      }, timeout);
      this.pending.set(id, { resolve, reject, timer });
      this.send({ id, method, params });
    });
  }
  notify(method, params) { this.send({ method, params }); }
  async waitExit(timeout) {
    let timer;
    try {
      return await Promise.race([this.exited, new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error(`TypeScript did not exit; ${this.errors}`)), timeout);
      })]);
    } finally { clearTimeout(timer); }
  }
  async stop() {
    if (!this.closed) this.child.kill('SIGTERM');
    try { await this.waitExit(2000); }
    catch { this.child.kill('SIGKILL'); await this.exited; }
  }
}

async function main() {
  assert.equal(process.getuid(), 1000);
  console.log(`GOPLS_RESOURCE_CLIENT_PID=${process.pid}`);
  assert.throws(() => fs.readlinkSync('/proc/self/exe'), { code: 'ENOENT' });
  fs.mkdirSync(workspace, { recursive: true });
  const env = { ...process.env, VIM_CONFIG_PROFILE: 'container', VIM_CONFIG_DENY_PATHS: '',
    XDG_CONFIG_HOME: path.join(workspace, 'config'),
    XDG_CACHE_HOME: path.join(workspace, 'cache'), PATH: '/usr/bin:/bin' };
  for (const name of ['NODE_OPTIONS', 'UV_THREADPOOL_SIZE', 'VIM_CONFIG_LOW_RESOURCE']) delete env[name];
  fs.writeFileSync(path.join(workspace, 'tsconfig.json'), JSON.stringify({
    compilerOptions: { target: 'ES2022', module: 'commonjs', strict: true }, include: ['*.ts'] }));
  const declaration = path.join(workspace, 'greeter.ts');
  fs.writeFileSync(declaration, 'export function greet(name: string): string { return "Hello " + name; }\n');
  fs.writeFileSync(path.join(workspace, 'extra.ts'), 'export const extra = { ready: true };\n');
  const source = path.join(workspace, 'main.ts');
  const lines = ['import { greet } from "./greeter";', 'import { extra } from "./extra";',
    'const message = greet("fixture");', 'const model = { greeting: message, count: 1, extra };', 'model.greet'];
  fs.writeFileSync(source, lines.join('\n') + '\n');
  const client = new Client(env);
  try {
    // Same options extracted from production Vim by the native regression.
    const initialized = await client.request('initialize', { processId: null, rootUri: uri(workspace),
      workspaceFolders: [{ uri: uri(workspace), name: 'fixture' }],
      capabilities: { textDocument: { completion: { completionItem: { snippetSupport: false } } } },
      initializationOptions: { disableAutomaticTypingAcquisition: true,
        preferences: { includeCompletionsForModuleExports: false }, tsserver: { useSyntaxServer: 'never' } } });
    assert.ok(initialized.capabilities, 'Initialize capabilities');
    client.notify('initialized', {});
    client.notify('textDocument/didOpen', { textDocument: { uri: uri(source), languageId: 'typescript',
      version: 1, text: fs.readFileSync(source, 'utf8') } });
    const definition = await client.request('textDocument/definition', { textDocument: { uri: uri(source) },
      position: { line: 2, character: lines[2].indexOf('greet') + 2 } });
    const locations = Array.isArray(definition) ? definition : [definition];
    assert.ok(locations.some(item => (item?.uri || item?.targetUri) === uri(declaration)), 'Cross-file definition');
    const completion = await client.request('textDocument/completion', { textDocument: { uri: uri(source) },
      position: { line: 4, character: lines[4].length }, context: { triggerKind: 1 } });
    assert.ok((completion?.items || completion || []).some(item => item.label === 'greeting'), 'Semantic property completion');
    console.log('NODE_RESOURCE_SEMANTIC_DEFINITION_COMPLETION_PASS');
    await client.request('shutdown', null, 3000);
    client.notify('exit', null);
    const exit = await client.waitExit(3000);
    assert.equal(exit.code, 0, 'Clean shutdown');
    console.log('VIM_LSP_RESOURCE_CLIENT_PASS');
  } finally { await client.stop(); }
}
main().catch(error => { console.error(error.stack || error); process.exitCode = 1; });
