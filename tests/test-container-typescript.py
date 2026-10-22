#!/usr/bin/env python3
"""Host-only regression: real container configuration, semantic TS, two PIDs.

Python and ps are needed only on the test host. Target installs use neither.
The process count is not a measurement or guarantee of a host's thread limit.
"""
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('vim_lsp_smoke', ROOT / 'tests/lsp-smoke.py')
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


def process_table():
    output = subprocess.check_output(['ps', '-axww', '-o', 'pid=,ppid=,command='], text=True)
    result = {}
    for line in output.splitlines():
        fields = line.strip().split(None, 2)
        if len(fields) == 3:
            result[int(fields[0])] = {'ppid': int(fields[1]), 'command': fields[2]}
    return result


def tree(pid, table):
    found = {pid}
    while True:
        children = {key for key, value in table.items() if value['ppid'] in found}
        if children <= found:
            return {key: table[key] for key in found if key in table}
        found |= children


def server_configuration(project, env):
    output = project / 'vim-typescript-config.json'
    select = 'let selected = filter(copy(g:lsp_servers), {_, server -> server.name ==# "typescript"})[0]'
    command = ('call writefile([json_encode({"path": selected.path, "args": selected.args, '
               '"initializationOptions": selected.initializationOptions})], $VIM_TS_CONFIG_OUTPUT)')
    subprocess.run([os.environ.get('VIM_TEST_BIN', 'vim'), '-Nu', str(ROOT / 'vimrc'),
                    '-i', 'NONE', '-n', '-es', '-c', select, '-c', command, '-c', 'qa!'],
                   env={**env, 'VIM_TS_CONFIG_OUTPUT': str(output)}, check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    configuration = json.loads(output.read_text())
    assert configuration['path'] == str(ROOT / 'bin/language-server')
    assert configuration['args'] == ['typescript']
    options = configuration['initializationOptions']
    assert options['disableAutomaticTypingAcquisition'] is True
    assert options['tsserver']['useSyntaxServer'] == 'never'
    return configuration


def check_tree(client):
    processes = tree(client.process.pid, process_table())
    commands = [item['command'] for item in processes.values()]
    assert len(processes) == 2, f'Expected parent + one tsserver; got {processes}'
    assert 'typescript-language-server/lib/cli.mjs' in processes[client.process.pid]['command']
    children = [item['command'] for pid, item in processes.items() if pid != client.process.pid]
    assert len(children) == 1 and 'typescript/lib/tsserver.js' in children[0], processes
    assert '--disableAutomaticTypingAcquisition' in children[0], processes
    assert not any('--serverMode' in item or '--syntaxOnly' in item or 'typingsInstaller' in item
                   for item in commands), processes
    return processes


def main():
    with tempfile.TemporaryDirectory(prefix='vim-container-typescript-') as directory:
        project = Path(directory).resolve()
        env = {**os.environ, 'VIM_CONFIG_PROFILE': 'container', 'VIM_CONFIG_DENY_PATHS': '',
               'XDG_CACHE_HOME': str(project / 'cache'),
               'XDG_CONFIG_HOME': str(project / 'config')}
        for name in ['NODE_OPTIONS', 'UV_THREADPOOL_SIZE', 'VIM_CONFIG_LOW_RESOURCE']:
            env.pop(name, None)
        (project / 'tsconfig.json').write_text(json.dumps({
            'compilerOptions': {'target': 'ES2022', 'module': 'commonjs', 'strict': True},
            'include': ['*.ts']}))
        declaration = project / 'greeter.ts'
        declaration.write_text('export function greet(name: string): string { return "Hello " + name; }\n')
        source = project / 'main.ts'
        lines = ['import { greet } from "./greeter";',
                 'const message = greet("fixture");',
                 'const model = { greeting: "hello", count: 1 };',
                 'model.greet']
        source.write_text('\n'.join(lines) + '\n')
        configuration = server_configuration(project, env)
        client = smoke.Client('typescript', project, env)
        observed = {}
        gracefully_exited = False
        try:
            initialized, initialize_ms = client.request('initialize', {
                'processId': os.getpid(), 'rootUri': project.as_uri(),
                'workspaceFolders': [{'uri': project.as_uri(), 'name': 'fixture'}],
                'capabilities': {'textDocument': {'completion': {'completionItem': {'snippetSupport': False}}}},
                'initializationOptions': configuration['initializationOptions']})
            assert initialized.get('capabilities'), 'Initialize capabilities missing'
            client.notify('initialized', {})
            client.open(source, 'typescript')
            definition, definition_ms = client.request('textDocument/definition', {
                'textDocument': {'uri': source.as_uri()},
                'position': {'line': 1, 'character': lines[1].index('greet') + 2}})
            locations = definition if isinstance(definition, list) else [definition]
            assert any((item.get('uri') or item.get('targetUri')) == declaration.as_uri()
                       for item in locations if item), f'Cross-file semantic definition missing: {definition}'
            observed.update(check_tree(client))
            completion, completion_ms = client.request('textDocument/completion', {
                'textDocument': {'uri': source.as_uri()},
                'position': {'line': 3, 'character': len(lines[3])},
                'context': {'triggerKind': 1}})
            items = completion.get('items', []) if isinstance(completion, dict) else completion
            assert any(item['label'] == 'greeting' for item in items or []), 'Inferred property completion missing'
            observed.update(check_tree(client))
            # Catch delayed child startup after the semantic workload finishes.
            for _ in range(3):
                time.sleep(.1)
                observed.update(check_tree(client))
            report = {'profile': 'container', 'initializationOptions': configuration['initializationOptions'],
                      'initialize_ms': initialize_ms, 'definition_ms': definition_ms,
                      'completion_ms': completion_ms, 'process_count': len(observed),
                      'processes': observed,
                      'boundary': 'PID tree only; host thread/total-process limits require separate measurement.'}
            # Do not use Client.close's test-cleanup kill fallback as evidence
            # of graceful server lifecycle: require the real protocol to exit.
            client.request('shutdown', None, 3)
            client.send({'method': 'exit'})
            assert client.process.wait(timeout=5) == 0, ''.join(client.errors)
            gracefully_exited = True
        finally:
            # Remember descendants even if a request failed before the checks.
            try:
                observed.update(tree(client.process.pid, process_table()))
            finally:
                if not gracefully_exited:
                    client.close()
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                remaining = {pid: info for pid, info in process_table().items()
                             if pid in observed and ('tsserver.js' in info['command'] or
                                                     'typescript-language-server/lib/cli.mjs' in info['command'])}
                if not remaining:
                    break
                time.sleep(.05)
            else:
                # Clean only fixture-owned, still-identifiable servers before
                # failing the lifecycle assertion; never leave a test daemon.
                for pid in remaining:
                    try:
                        os.kill(pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                raise AssertionError(f'TypeScript descendants survived shutdown: {remaining}')
        output = ROOT / '.state/tests/container-typescript.json'
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, indent=2) + '\n')
        print('PASS: container TypeScript (production Vim options, semantic definition/completion, '
              'one tsserver child, no separate syntax/ATA, clean shutdown)', flush=True)


if __name__ == '__main__':
    main()
