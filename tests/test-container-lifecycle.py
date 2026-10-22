#!/usr/bin/env python3
"""Host-only real-Vim lifecycle regression; never installs target dependencies."""
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def check_preload(fixture):
    platform = 'darwin-arm64' if os.uname().sysname == 'Darwin' else 'linux-x86_64'
    node = ROOT / '.state/tools' / platform / 'bin/node'
    (fixture / 'delayed-child.cjs').write_text('''
const fs = require('node:fs');
process.on('SIGTERM', () => {
  fs.writeFileSync(process.argv[2] + '.term', 'term');
  setTimeout(() => { fs.writeFileSync(process.argv[2] + '.done', 'done'); process.exit(0); }, 400);
});
setInterval(() => {}, 1000);
if (process.send) process.send('ready'); else process.stdout.write('ready\\n');
''')
    (fixture / 'delayed-parent.mjs').write_text('''
import { spawn, fork } from 'node:child_process';
const [mode, childFile, marker] = process.argv.slice(2);
const child = mode === 'fork' ? fork(childFile, [marker]) : spawn(process.execPath, [childFile, marker]);
let stopping = false;
const stop = () => { if (stopping) return; stopping = true; child.kill('SIGTERM'); process.exit(0); };
if (mode === 'fork') child.once('message', stop); else child.stdout.once('data', stop);
''')
    for mode in ['fork', 'spawn']:
        marker = fixture / ('delayed-' + mode)
        process = subprocess.Popen([str(node), '--require', str(ROOT / 'libexec/typescript-lifecycle.cjs'),
                                    str(fixture / 'delayed-parent.mjs'), mode,
                                    str(fixture / 'delayed-child.cjs'), str(marker)],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        try:
            deadline = time.monotonic() + 5
            while not Path(str(marker) + '.term').exists():
                assert process.poll() is None, 'preload parent exited before delayed child acknowledged TERM'
                assert time.monotonic() < deadline, 'delayed child did not receive TERM'
                time.sleep(.01)
            assert process.poll() is None, 'preload failed to wait for child close'
            output, errors = process.communicate(timeout=5)
            assert process.returncode == 0, (output, errors)
            assert Path(str(marker) + '.done').exists(), 'parent exited before child completed cleanup'
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()


def main():
    with tempfile.TemporaryDirectory(prefix='vim-container-lifecycle-') as directory:
        fixture = Path(directory).resolve()
        check_preload(fixture)
        (fixture / 'main.ts').write_text('function originalName(): string { return "fixture"; }\noriginalName();\n')
        (fixture / 'same.js').write_text('export function sameFamily() { return 1; }\n')
        (fixture / 'tsconfig.json').write_text('{"compilerOptions":{"allowJs":true},"include":["*.ts","*.js"]}\n')
        (fixture / 'composer.json').write_text('{}\n')
        (fixture / 'app.php').write_text('<?php\nfunction phpFixture() { return 1; }\nphpFixture();\n')
        (fixture / 'slow.fixture').write_text('fixture\n')
        (fixture / 'slow.py').write_text('''import json, signal, sys, time
from pathlib import Path
def signaled(sig, frame):
    Path(sys.argv[1]).write_text(str(sig))
    raise SystemExit(99)
signal.signal(signal.SIGTERM, signaled)
while True:
    headers = {}
    while True:
        line = sys.stdin.buffer.readline()
        if not line: raise SystemExit(0)
        if line == b'\\r\\n': break
        key, value = line.decode().split(':', 1)
        headers[key.lower()] = value.strip()
    message = json.loads(sys.stdin.buffer.read(int(headers['content-length'])))
    method = message.get('method')
    if method == 'exit':
        time.sleep(.5)
        raise SystemExit(0)
    if 'id' in message:
        result = {'capabilities': {}} if method == 'initialize' else None
        body = json.dumps({'jsonrpc':'2.0','id':message['id'],'result':result}).encode()
        sys.stdout.buffer.write(('Content-Length: %s\\r\\n\\r\\n' % len(body)).encode() + body)
        sys.stdout.buffer.flush()
''')
        module = str(ROOT / 'vendor/pack/vim-config/start/lsp/autoload/lsp/lsp.vim').replace("'", "''")
        (fixture / 'bridge.vim').write_text("vim9script\nimport autoload '" + module + "' as lsp\n"
            'def g:VimConfigTestServer(): dict<any>\n  return lsp.Server()\nenddef\n')
        (fixture / 'driver.vim').write_text(r'''
set nomore
set viminfo=
let s:fixture = $VIM_LIFECYCLE_FIXTURE
execute 'source ' . fnameescape(s:fixture . '/bridge.vim')
function! s:ready() abort
  let started = reltime()
  while reltimefloat(reltime(started)) < 20
    if g:LspServerReady() | return 1 | endif
    sleep 100m
    " Retry a safe refusal if a preceding family finished after its deadline.
    doautocmd BufEnter
  endwhile
  return 0
endfunction
try
  call g:LspEnable()
  execute 'edit ' . fnameescape(s:fixture . '/main.ts')
  call assert_equal(1, s:ready(), 'initial TS ready')
  let s:tsbuffer = bufnr()
  let s:tsjob = g:VimConfigTestServer().job
  let s:tspid = job_info(s:tsjob).process
  execute 'edit ' . fnameescape(s:fixture . '/same.js')
  call assert_equal(1, s:ready(), 'JS variant ready')
  call assert_equal(s:tspid, job_info(g:VimConfigTestServer().job).process, 'JS/TS switched the shared family')
  let s:jsbuffer = bufnr()
  call setline(1, 'export function hiddenUnsavedName() { return 2; }')
  execute 'buffer ' . s:tsbuffer
  call setline(1, ['function unsavedName(): string { return "fixture"; }', 'unsavedName();',
        \ 'import { hiddenUnsavedName } from "./same";', 'hiddenUnsavedName();'])
  call assert_equal(1, &modified)
  execute 'edit ' . fnameescape(s:fixture . '/app.php')
  call assert_equal(1, s:ready(), 'PHP ready after TS')
  call assert_equal('dead', job_status(s:tsjob), 'TS parent still alive after switching family')
  let s:phpjob = g:VimConfigTestServer().job
  let s:phpserver = g:VimConfigTestServer()
  let s:phpserver.debug = v:true
  let s:phpserver.logfile = fnamemodify(s:fixture, ':t') . '-php.log'
  let s:phpserver.errfile = fnamemodify(s:fixture, ':t') . '-php.err'
  execute 'buffer ' . s:tsbuffer
  call assert_equal(1, s:ready(), 'TS restarted after PHP')
  call assert_equal('dead', job_status(s:phpjob), 'PHP still alive after switching family')
  call assert_notequal(s:tspid, job_info(g:VimConfigTestServer().job).process, 'TS process did not restart')
  call assert_equal(1, &modified, 'dirty buffer lost modified flag')
  call assert_match('unsavedName', getline(1), 'dirty text lost during family switch')
  call cursor(2, 4)
  LspGotoDefinition
  call assert_equal(1, line('.'), 'reactivated TS did not receive unsaved definition')
  call assert_match('unsavedName', getline('.'))
  call assert_match('originalName', readfile(s:fixture . '/main.ts')[0], 'family switch wrote unsaved text to disk')
  call cursor(4, 4)
  LspGotoDefinition
  call assert_equal(s:jsbuffer, bufnr(), 'hidden dirty JS buffer was not reopened with its unsaved contents')
  call assert_equal(1, &modified, 'hidden buffer lost modified flag')
  call assert_match('hiddenUnsavedName', getline('.'))
  execute 'buffer ' . s:tsbuffer
  call g:LspAddServer([{'name':'slow-fixture', 'filetype':['vclifecycle'], 'path':exepath('python3'),
         \ 'args':[s:fixture . '/slow.py', s:fixture . '/signal'], 'rootSearch':[]}])
  execute 'edit ' . fnameescape(s:fixture . '/slow.fixture')
  setfiletype vclifecycle
  call assert_equal(1, s:ready(), 'slow fixture ready')
  let s:slowjob = g:VimConfigTestServer().job
  let g:vimconfig_family_stop_timeout = 0.01
  execute 'edit ' . fnameescape(s:fixture . '/app.php')
  call assert_equal('run', job_status(s:slowjob), 'slow fixture was force-terminated')
  call assert_false(g:LspServerRunning('php'), 'new family started while previous family remained alive')
  call assert_false(filereadable(s:fixture . '/signal'), 'lifecycle sent termination signal')
  sleep 700m
  doautocmd BufEnter
  call assert_equal(1, s:ready(), 'retry did not activate new family after graceful exit')
  call assert_equal('dead', job_status(s:slowjob))
  " Simulate the bundled PHP indexer acknowledging then lingering after exit.
  " Only its production name/path/args identity is eligible for TERM fallback.
  execute 'edit ' . fnameescape(s:fixture . '/slow.fixture')
  call assert_equal(1, s:ready(), 'second slow fixture ready')
  let s:phpsim = g:VimConfigTestServer()
  let s:phpsimjob = s:phpsim.job
  let s:phpsim.name = 'php'
  let s:phpsim.path = g:vimconfig_root . '/bin/language-server'
  let s:phpsim.args = ['php']
  execute 'edit ' . fnameescape(s:fixture . '/app.php')
  call assert_equal(1, s:ready(), 'PHP-only TERM fallback did not permit next family after exit')
  call assert_equal('dead', job_status(s:phpsimjob), 'next family overlapped the PHP fixture')
  call assert_true(filereadable(s:fixture . '/signal'), 'known PHP fixture did not receive TERM fallback')
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, s:fixture . '/errors')
call writefile(split(execute('messages'), "\n"), s:fixture . '/messages')
if !empty(v:errors) | cquit | endif
qa!
''')
        env = {**os.environ, 'VIM_CONFIG_PROFILE': 'container', 'VIM_CONFIG_DENY_PATHS': '',
               'VIM_LIFECYCLE_FIXTURE': str(fixture), 'XDG_CACHE_HOME': str(fixture / 'cache'),
               'XDG_CONFIG_HOME': str(fixture / 'config')}
        command = [os.environ.get('VIM_TEST_BIN', 'vim'), '-Nu', str(ROOT / 'vimrc'),
                   '-i', 'NONE', '-n', '-es', '-S', str(fixture / 'driver.vim')]
        result = subprocess.run(command, env=env, cwd=fixture, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
        errors = (fixture / 'errors').read_text() if (fixture / 'errors').exists() else 'driver did not finish'
        messages = (fixture / 'messages').read_text() if (fixture / 'messages').exists() else ''
        log = Path('/tmp') / (fixture.name + '-php.log')
        errlog = Path('/tmp') / (fixture.name + '-php.err')
        trace = log.read_text() if log.exists() else ''
        stderr = errlog.read_text() if errlog.exists() else ''
        for output in [log, errlog]:
            if output.exists():
                output.unlink()
        assert result.returncode == 0, errors + '\n' + result.stdout.decode(errors='replace') + '\n' + messages + '\n' + trace[-20000:] + '\n' + stderr
        print('PASS: container lifecycle (JS/TS reuse, graceful switch/restart, dirty buffers, refusal/retry, bounded PHP-only TERM)', flush=True)


if __name__ == '__main__':
    main()
