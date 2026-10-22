#!/usr/bin/env python3
"""Real offline server acceptance tests; Python is needed only on the test host."""
import json
import os
from pathlib import Path
import queue
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]


class Client:
    def __init__(self, server, project, env):
        self.server = server
        self.process = subprocess.Popen(
            [str(ROOT / 'bin/language-server'), server], cwd=project,
            env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE)
        self.messages = queue.Queue()
        self.errors = []
        self.serial = 0
        threading.Thread(target=self.read, daemon=True).start()
        threading.Thread(target=self.read_errors, daemon=True).start()

    def read_errors(self):
        for line in self.process.stderr:
            self.errors.append(line.decode(errors='replace'))

    def read(self):
        try:
            while True:
                headers = {}
                while True:
                    line = self.process.stdout.readline()
                    if not line:
                        self.messages.put(RuntimeError('server closed stdout'))
                        return
                    if line == b'\r\n':
                        break
                    key, value = line.decode().split(':', 1)
                    headers[key.lower()] = value.strip()
                length = int(headers['content-length'])
                payload = b''
                while len(payload) < length:
                    payload += self.process.stdout.read(length - len(payload))
                self.messages.put(json.loads(payload))
        except Exception as exc:
            self.messages.put(exc)

    def send(self, message):
        payload = json.dumps({'jsonrpc': '2.0', **message}).encode()
        self.process.stdin.write(f'Content-Length: {len(payload)}\r\n\r\n'.encode() + payload)
        self.process.stdin.flush()

    def notify(self, method, params):
        self.send({'method': method, 'params': params})

    def request(self, method, params, timeout=45):
        self.serial += 1
        ident = self.serial
        start = time.monotonic()
        self.send({'id': ident, 'method': method, 'params': params})
        deadline = start + timeout
        while time.monotonic() < deadline:
            message = self.messages.get(timeout=max(.01, deadline - time.monotonic()))
            if isinstance(message, Exception):
                raise RuntimeError(f'{message}: {"".join(self.errors)[-2000:]}')
            if 'method' in message and 'id' in message:
                result = None
                if message['method'] == 'workspace/configuration':
                    result = [{} for _ in message.get('params', {}).get('items', [])]
                elif message['method'] == 'workspace/applyEdit':
                    result = {'applied': False}
                self.send({'id': message['id'], 'result': result})
            elif message.get('id') == ident:
                if 'error' in message:
                    raise AssertionError(f'{method}: {message["error"]}')
                return message.get('result'), round((time.monotonic() - start) * 1000, 2)
        raise TimeoutError(method)

    def initialize(self, project):
        init = {'disableAutomaticTypingAcquisition': True}
        if self.server == 'json':
            init = {'handledSchemaProtocols': ['file'], 'provideFormatter': True}
        elif self.server in ('html', 'css'):
            init = {'provideFormatter': True}
        result, elapsed = self.request('initialize', {
            'processId': os.getpid(), 'rootUri': project.as_uri(),
            'workspaceFolders': [{'uri': project.as_uri(), 'name': 'fixture'}],
            'capabilities': {'textDocument': {'completion': {'completionItem': {'snippetSupport': False}}, 'callHierarchy': {}}},
            'initializationOptions': init})
        assert 'capabilities' in result
        self.notify('initialized', {})
        return elapsed

    def open(self, path, language):
        self.notify('textDocument/didOpen', {'textDocument': {
            'uri': path.as_uri(), 'languageId': language, 'version': 1,
            'text': path.read_text()}})

    def close(self):
        try:
            self.request('shutdown', None, 3)
            self.notify('exit', None)
            self.process.wait(timeout=3)
        except Exception:
            self.process.kill()
            self.process.wait()


def main():
    report = {'host': os.uname().sysname + '-' + os.uname().machine, 'results': {}}
    with tempfile.TemporaryDirectory(prefix='vim-config-acceptance-') as temp:
        project = Path(temp).resolve()
        env = {**os.environ, 'VIM_CONFIG_PROFILE': 'laptop' if os.uname().sysname == 'Darwin' else 'container',
               'XDG_CACHE_HOME': str(project / 'cache'), 'XDG_CONFIG_HOME': str(project / 'config'),
               'GOCACHE': str(project / 'gocache'), 'GOMODCACHE': str(project / 'gomodcache'),
               'GOPATH': str(project / 'gopath'), 'GOTELEMETRYDIR': str(project / 'telemetry')}
        (project / 'composer.json').write_text('{"autoload":{"classmap":["./"]}}\n')
        lines = ['<?php']
        for number in range(500):
            lines.append(f'function worker_{number:04d}(string $input): string {{')
            for step in range(27):
                lines.append(f"    $value_{step:02d} = $input . '-operation-{step:02d}';")
            lines += ['    return $value_26;', '}']
        call_line = len(lines)
        lines.append("function benchmarkCaller(): string { return worker_0000('input'); }")
        completion_line = len(lines)
        lines.append('worker_00();')
        large = project / 'large.php'
        large.write_text('\n'.join(lines) + '\n')
        report['php_fixture'] = {'bytes': large.stat().st_size, 'lines': len(lines)}
        client = Client('php', project, env)
        try:
            result = {'initialize_ms': client.initialize(project)}
            client.open(large, 'php')
            position = {'line': call_line, 'character': lines[call_line].index('worker_0000') + 3}
            definition, result['first_definition_ms'] = client.request('textDocument/definition', {
                'textDocument': {'uri': large.as_uri()}, 'position': position})
            assert definition, 'PHP definition missing'
            completion, result['completion_ms'] = client.request('textDocument/completion', {
                'textDocument': {'uri': large.as_uri()}, 'position': {'line': completion_line, 'character': 9},
                'context': {'triggerKind': 1}})
            items = completion.get('items', []) if isinstance(completion, dict) else completion
            assert any('worker_0000' in item['label'] for item in items), 'PHP completion missing'
            hierarchy, result['prepare_calls_ms'] = client.request('textDocument/prepareCallHierarchy', {
                'textDocument': {'uri': large.as_uri()}, 'position': {'line': 1, 'character': 14}})
            assert hierarchy, 'PHP call hierarchy unavailable'
            callers, result['incoming_calls_ms'] = client.request('callHierarchy/incomingCalls', {'item': hierarchy[0]})
            assert any(item['from']['name'] == 'benchmarkCaller' for item in callers), 'PHP caller missing'
            changed = '// edited fixture\n'
            client.notify('textDocument/didChange', {'textDocument': {'uri': large.as_uri(), 'version': 2},
                'contentChanges': [{'range': {'start': {'line': 1, 'character': 0}, 'end': {'line': 1, 'character': 0}}, 'text': changed}]})
            definition, result['definition_after_edit_ms'] = client.request('textDocument/definition', {
                'textDocument': {'uri': large.as_uri()}, 'position': {**position, 'line': call_line + 1}})
            if not definition:
                print('PHP definition immediately after edit was empty; checking eventual update', flush=True)
                time.sleep(.1)
                definition, result['definition_after_edit_retry_ms'] = client.request('textDocument/definition', {
                    'textDocument': {'uri': large.as_uri()}, 'position': {**position, 'line': call_line + 1}})
            assert definition, 'PHP definition lost after edit'
            report['results']['php'] = result
        finally:
            client.close()

        fixtures = {
            'typescript': ('sample.js', 'javascript', 'function greet(name) { return name; }\ngreet("fixture");\n',
                           {'line': 1, 'character': 2}),
            'html': ('sample.html', 'html', '<!doctype html>\n<html><body><di</body></html>\n', {'line': 1, 'character': 15}),
            'css': ('sample.css', 'css', 'body { col }\n', {'line': 0, 'character': 10}),
            'json': ('sample.json', 'json', '{"name": "fixture"}\n', {'line': 0, 'character': 2}),
            'go': ('sample.go', 'go', 'package probe\nimport "fmt"\nfunc Example() { fmt.Println("fixture") }\n', {'line': 2, 'character': 22}),
        }
        (project / 'go.mod').write_text('module fixture.invalid/probe\n\ngo 1.23\n')
        for server, (name, language, text, position) in fixtures.items():
            path = project / name
            path.write_text(text)
            client = Client(server, project, env)
            try:
                result = {'initialize_ms': client.initialize(project)}
                client.open(path, language)
                method = 'textDocument/definition' if server in ('typescript', 'go') else 'textDocument/documentSymbol'
                params = {'textDocument': {'uri': path.as_uri()}}
                if method.endswith('definition'):
                    params['position'] = position
                response, result['request_ms'] = client.request(method, params, timeout=90)
                assert response, f'{server} {method} missing'
                if server in ('html', 'css'):
                    completion, result['completion_ms'] = client.request('textDocument/completion', {
                        'textDocument': {'uri': path.as_uri()}, 'position': position})
                    assert completion, f'{server} completion missing'
                if server in ('html', 'css', 'json'):
                    edits, result['format_ms'] = client.request('textDocument/formatting', {
                        'textDocument': {'uri': path.as_uri()}, 'options': {'tabSize': 4, 'insertSpaces': True}})
                    assert isinstance(edits, list), f'{server} formatter missing'
                report['results'][server] = result
            finally:
                client.close()
    out = ROOT / '.state/lsp-smoke.json'
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2), flush=True)


if __name__ == '__main__':
    main()
