// Disposable Linux resource workload; no user projects or network.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { Client } = require('./gopls-no-proc.cjs');

async function main() {
  assert.equal(process.getuid(), 1000);
  assert.throws(() => fs.readlinkSync('/proc/self/exe'), { code: 'ENOENT' });
  console.log(`GOPLS_RESOURCE_CLIENT_PID=${process.pid}`);
  const workspace = process.env.VIM_QEMU_GOPLS_WORKSPACE;
  const env = { ...process.env, VIM_CONFIG_PROFILE: 'container', VIM_CONFIG_DENY_PATHS: '',
    XDG_CACHE_HOME: path.join(workspace, 'cache'),
    XDG_CONFIG_HOME: path.join(workspace, 'config'), PATH: '/usr/bin:/bin' };
  for (const key of ['RAYON_NUM_THREADS', 'TOKIO_WORKER_THREADS', 'GOMAXPROCS', 'UV_THREADPOOL_SIZE', 'NODE_OPTIONS']) delete env[key];
  for (const directory of [env.XDG_CACHE_HOME, env.XDG_CONFIG_HOME, path.join(workspace, 'src')]) fs.mkdirSync(directory, { recursive: true });
  const documents = [];
  for (let index = 0; index < 100; index++) {
    const file = path.join(workspace, 'src', `Function${index}.php`);
    const text = `<?php\nfunction resource_probe_${index}(): string { return "value-${index}"; }\n`;
    fs.writeFileSync(file, text);
    documents.push({ file, text });
  }
  const largeFile = path.join(workspace, 'src', 'Large.php');
  const largeText = '<?php\n' + Array.from({ length: 3750 }, (_, index) =>
    `function resource_large_${index}(int $value): int {\n    $adjusted = $value + ${index}; // local application logic\n    return $adjusted;\n}\n`).join('');
  fs.writeFileSync(largeFile, largeText);
  documents.push({ file: largeFile, text: largeText });
  const app = path.join(workspace, 'app.php');
  const text = "<?php\nrequire_once __DIR__ . '/src/Function42.php';\nresource_probe_42();\nresource_probe_\n";
  fs.writeFileSync(app, text);
  const client = new Client(process.env.VIM_QEMU_LSP_LAUNCHER || '/opt/vim-config/bin/language-server', ['php'], env, workspace);
  try {
    const result = await client.request('initialize', { processId: null, rootUri: pathToFileURL(workspace).href,
      workspaceFolders: [{ uri: pathToFileURL(workspace).href, name: 'cold-php-resource-fixture' }], capabilities: {},
      initializationOptions: process.env.VIM_QEMU_PHP_DEFAULT_DIAGNOSTICS === '1' ? {} : {
        indexing: { exclude: ['**/wp-content/blogs.dir/**'], strategy: 'full' },
        diagnostics: { workspace: false } } }, 30000);
    assert.ok(result.capabilities);
    client.notify('initialized', {});
    for (const document of [...documents, { file: app, text }]) client.notify('textDocument/didOpen', { textDocument: {
      uri: pathToFileURL(document.file).href, languageId: 'php', version: 1, text: document.text } });
    const params = { textDocument: { uri: pathToFileURL(app).href }, position: { line: 2, character: 7 } };
    let definition;
    for (let attempt = 0; attempt < 15; attempt++) {
      definition = await client.request('textDocument/definition', params, 15000);
      if (JSON.stringify(definition).includes('Function42.php')) break;
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    assert.ok(JSON.stringify(definition).includes('Function42.php'), `cross-file PHP definition: ${JSON.stringify(definition)}`);
    const completion = await client.request('textDocument/completion', { textDocument: params.textDocument,
      position: { line: 3, character: 15 }, context: { triggerKind: 1 } });
    const items = Array.isArray(completion) ? completion : completion?.items;
    assert.ok(items?.some(item => String(item.label).includes('resource_probe_42')), 'PHP completion includes an indexed function');
    await client.request('shutdown', undefined, 3000);
    client.notify('exit', undefined);
    // Mirror Vim's teardown: PHPantom also needs its input closed after exit.
    client.child.stdin.end();
    const exit = await client.waitExit(5000);
    assert.equal(exit.code, 0, 'clean PHP shutdown after stdin EOF');
    console.log(`VIM_LSP_RESOURCE_CLIENT_PASS php ${documents.length + 1}-files large-file-bytes=${Buffer.byteLength(largeText)} large-file-lines=15001 workspace-diagnostics=${process.env.VIM_QEMU_PHP_DEFAULT_DIAGNOSTICS === '1' ? 'default' : 'off'} cross-file-definition completion clean-exit=0`);
  } finally { await client.stop(); }
}
main().catch(error => { console.error(error.stack || error); process.exitCode = 1; });
