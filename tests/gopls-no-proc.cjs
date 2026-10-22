// Linux QEMU fixture client. No network, dependencies, or user projects.
// Run only after /proc has been unmounted in a disposable mount namespace.
'use strict';
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { pathToFileURL, fileURLToPath } = require('node:url');

const workspace = process.env.VIM_QEMU_GOPLS_WORKSPACE || '/home/tester/gopls-no-proc';
const patched = '/opt/vim-tools/bin/gopls';
const upstream = '/opt/vim-tools/bin/gopls-upstream';
const launcher = '/opt/vim-config/bin/language-server';
const sdk = '/opt/vim-tools/go';
const deadline = Number(process.env.VIM_QEMU_GOPLS_TIMEOUT || 180) * 1000;
const roots = [workspace];
for (let index = 2; index <= Number(process.env.VIM_QEMU_GOPLS_ROOTS || 1); index++) roots.push(path.join(workspace, `module-${index}`));

class Client {
  constructor(command, args, environment, cwd = workspace) {
    this.buffer = Buffer.alloc(0);
    this.stderr = '';
    this.pending = new Map();
    this.nextId = 1;
    this.closed = false;
    if (process.env.VIM_QEMU_GOPLS_RESOURCE_EVENTS === '1') {
      this.child = spawn('/bin/sh', ['-c', 'kill -STOP "$$"; exec "$@"', 'go-resource-fixture', command, ...args],
        { cwd, env: environment, stdio: ['pipe', 'pipe', 'pipe'] });
      console.log(`GOPLS_RESOURCE_CHILD_PID=${this.child.pid}`);
    } else this.child = spawn(command, args, { cwd, env: environment, stdio: ['pipe', 'pipe', 'pipe'] });
    this.child.stdin.on('error', () => {});
    this.child.stdout.on('data', chunk => this.output(chunk));
    this.child.stderr.on('data', chunk => { this.stderr = (this.stderr + chunk.toString()).slice(0, 16384); });
    this.exited = new Promise(resolve => {
      this.child.once('close', (code, signal) => {
        this.closed = true;
        this.exit = { code, signal };
        for (const { reject, timer } of this.pending.values()) {
          clearTimeout(timer);
          reject(new Error(`server closed: code=${code}, signal=${signal}; ${this.stderr}`));
        }
        this.pending.clear();
        resolve(this.exit);
      });
      this.child.once('error', error => {
        this.stderr += String(error);
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
      const length = /^Content-Length:\s*(\d+)\s*$/im.exec(this.buffer.subarray(0, end).toString());
      if (!length) throw new Error('invalid LSP framing');
      const count = Number(length[1]);
      if (this.buffer.length < end + 4 + count) return;
      const message = JSON.parse(this.buffer.subarray(end + 4, end + 4 + count).toString());
      this.buffer = this.buffer.subarray(end + 4 + count);
      if (message.method && Object.hasOwn(message, 'id')) {
        let result = null;
        if (message.method === 'workspace/configuration') result = (message.params?.items || []).map(() => ({}));
        if (message.method === 'workspace/workspaceFolders') result = [{ uri: pathToFileURL(workspace).href, name: 'fixture' }];
        this.send({ id: message.id, result });
      } else if (Object.hasOwn(message, 'id')) {
        const pending = this.pending.get(message.id);
        if (!pending) continue;
        clearTimeout(pending.timer);
        this.pending.delete(message.id);
        if (message.error) pending.reject(new Error(JSON.stringify(message.error)));
        else pending.resolve(message.result);
      }
    }
  }
  request(method, params, timeout = deadline) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`timeout waiting for ${method}; ${this.stderr}`));
      }, timeout);
      this.pending.set(id, { resolve, reject, timer });
      this.send({ id, method, params });
    });
  }
  notify(method, params) { this.send({ method, params }); }
  async waitExit(milliseconds) {
    let timer;
    try {
      return await Promise.race([this.exited, new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error(`server did not exit; ${this.stderr}`)), milliseconds);
      })]);
    } finally { clearTimeout(timer); }
  }
  async stop() {
    if (!this.closed) this.child.kill('SIGTERM');
    try { await this.waitExit(1500); }
    catch { this.child.kill('SIGKILL'); await this.exited; }
  }
}

function environment(name, fallback, throughLauncher = false) {
  const fixture = path.join(workspace, name);
  const env = { ...process.env,
    HOME: path.join(fixture, 'home'), XDG_CONFIG_HOME: path.join(fixture, 'config'),
    XDG_CACHE_HOME: path.join(fixture, 'cache'), GOCACHE: path.join(workspace, 'go-build-cache'),
    GOPLSCACHE: path.join(fixture, 'gopls-cache'), GOPATH: path.join(fixture, 'gopath'),
    GOMODCACHE: path.join(fixture, 'gomodcache'), GOENV: 'off', GOTOOLCHAIN: 'local',
    GOPROXY: 'off', GOSUMDB: 'off', CGO_ENABLED: '0',
    VIM_CONFIG_PROFILE: 'container', VIM_CONFIG_DENY_PATHS: '',
    PATH: throughLauncher ? '/usr/bin:/bin' : `${sdk}/bin:/usr/bin:/bin`,
  };
  // The positive case deliberately relies on the real launcher to set GOROOT
  // and the exact fallback binary. Direct negative cases isolate hash failure.
  if (throughLauncher) {
    delete env.GOROOT;
    delete env.GOMAXPROCS;
    delete env.GOFLAGS;
    delete env.GOMEMLIMIT;
  } else {
    env.GOROOT = sdk;
    if (process.env.VIM_QEMU_GOPLS_RAW === '1') {
      delete env.GOMAXPROCS;
      delete env.GOMEMLIMIT;
      env.GOFLAGS = '-mod=readonly';
    } else {
      env.GOMAXPROCS = '1';
      env.GOFLAGS = '-p=1 -mod=readonly';
      env.GOMEMLIMIT = '256MiB';
      env.VIM_CONFIG_LOW_RESOURCE = '1';
    }
  }
  if (fallback === undefined) delete env.VIM_CONFIG_GOPLS_EXECUTABLE;
  else env.VIM_CONFIG_GOPLS_EXECUTABLE = fallback;
  delete env.GOTELEMETRY;
  delete env.GOTELEMETRYDIR;
  for (const directory of [env.HOME, path.join(env.XDG_CONFIG_HOME, 'go/telemetry')]) fs.mkdirSync(directory, { recursive: true });
  fs.writeFileSync(path.join(env.XDG_CONFIG_HOME, 'go/telemetry/mode'), 'off\n');
  return env;
}

function initialize(client) {
  return client.request('initialize', { processId: null,
    rootUri: pathToFileURL(workspace).href, workspaceFolders: roots.map((folder, index) => ({ uri: pathToFileURL(folder).href, name: `fixture-${index}` })),
    capabilities: {}, initializationOptions: {},
  }, 20000);
}

async function rejected(name, executable, fallback, requiredText) {
  const client = new Client(executable, [], environment(name, fallback));
  try {
    // Cache initialization is asynchronous; initialize can reply before fatal.
    await initialize(client).catch(() => {});
    const exit = await client.waitExit(20000);
    assert.notEqual(exit.code, 0, `${name}: expected filecache failure`);
    assert.match(client.stderr, /cannot access its persistent index/);
    assert.match(client.stderr, requiredText);
    console.log(`GOPLS_NO_PROC_EXPECTED_FAILURE ${name}: code=${exit.code}; ${client.stderr.split('\n')[0]}`);
  } finally { await client.stop(); }
}

async function working() {
  const direct = process.env.VIM_QEMU_GOPLS_EXECUTABLE;
  const executable = direct || patched;
  const env = environment('patched-wrapper', direct, !direct);
  const client = new Client(direct || launcher, direct ? [] : ['go'], env);
  try {
    const initialized = await initialize(client);
    assert.ok(initialized.capabilities, 'launcher initialize capabilities');
    client.notify('initialized', {});
    const documents = roots.map(folder => path.join(folder, 'probe.go'));
    for (const document of documents) client.notify('textDocument/didOpen', { textDocument: {
      uri: pathToFileURL(document).href, languageId: 'go', version: 1, text: fs.readFileSync(document, 'utf8'),
    } });
    for (const locations of await Promise.all(documents.map(document => client.request('textDocument/definition', {
      textDocument: { uri: pathToFileURL(document).href }, position: { line: 2, character: 22 },
    })))) {
      const entries = Array.isArray(locations) ? locations : [locations];
      const definition = entries.find(item => /\/src\/fmt\/print\.go$/.test(item?.uri || item?.targetUri || ''));
      assert.ok(definition, `stdlib definition: ${JSON.stringify(locations)}`);
      assert.ok(fs.statSync(fileURLToPath(definition.uri || definition.targetUri)).isFile());
    }
    // The fallback must preserve content-addressed cache identity.
    const digest = crypto.createHash('sha256').update(fs.readFileSync(executable)).digest();
    const recorded = fs.readFileSync(path.join(env.GOPLSCACHE, 'gopls', digest.toString('hex').slice(0, 8), 'exe.sha256'));
    assert.ok(recorded.equals(digest), 'cache fingerprint must match patched executable bytes');
    console.log(direct ? 'GOPLS_NO_PROC_DIRECT_STDLIB_PASS' : 'GOPLS_NO_PROC_WRAPPER_STDLIB_PASS');
    console.log(`GOPLS_NO_PROC_CONTENT_HASH_PASS ${digest.toString('hex')}`);
    await client.request('shutdown', null, 3000);
    client.notify('exit', null);
    await client.waitExit(3000);
  } finally { await client.stop(); }
}

async function main() {
  assert.equal(process.getuid(), 1000);
  if (process.env.VIM_QEMU_GOPLS_RESOURCE_EVENTS === '1') console.log(`GOPLS_RESOURCE_CLIENT_PID=${process.pid}`);
  assert.throws(() => fs.readlinkSync('/proc/self/exe'), { code: 'ENOENT' });
  console.log('GOPLS_NO_PROC_CONTROL_ENOENT');
  for (const [index, folder] of roots.entries()) {
    fs.mkdirSync(folder, { recursive: true });
    fs.writeFileSync(path.join(folder, 'go.mod'), `module regression.invalid/probe${index}\n\ngo 1.23\n`);
    fs.writeFileSync(path.join(folder, 'probe.go'), 'package probe\nimport "fmt"\nfunc Example() { fmt.Println("fixture") }\n');
  }
  const unreadable = path.join(workspace, 'unreadable-executable');
  fs.writeFileSync(unreadable, 'fixture');
  fs.chmodSync(unreadable, 0);
  if (process.env.VIM_QEMU_GOPLS_WORKING_ONLY !== '1') {
    await rejected('upstream', upstream, upstream, /readlink \/proc\/self\/exe: no such file or directory/);
    await rejected('missing-fallback', patched, undefined, /VIM_CONFIG_GOPLS_EXECUTABLE/);
    await rejected('relative-fallback', patched, 'relative/gopls', /VIM_CONFIG_GOPLS_EXECUTABLE/);
    await rejected('missing-file-fallback', patched, '/no-such-fixture-executable', /no-such-fixture-executable/);
    await rejected('unreadable-fallback', patched, unreadable, /permission denied/);
  }
  await working();
  console.log('VIM_GOPLS_NO_PROC_REGRESSION_PASS');
}
module.exports = { Client };
if (require.main === module) main().catch(error => { console.error(error.stack || error); process.exitCode = 1; });
