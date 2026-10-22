#!/usr/bin/env python3
"""Maintainer-only reproducible preparation; normal installation is fully offline.

--verify checks committed archives and their Bash table without downloading. --rebuild deliberately
uses the network and compiler on a preparation machine, never on target hosts.
"""
import argparse
import concurrent.futures
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import posixpath
import re
import shutil
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'tools/vendor-manifest.json'
PAYLOADS_TSV = ROOT / 'tools/payloads.tsv'


def payloads_tsv(manifest):
    """Generate the deliberately small, strict format consumed by Bash setup.

    Six tab-separated ASCII fields, no escaping, with two comment header lines.
    Only single-part gzip tar archives and the two supported platforms are
    representable. Paths are relative to the checkout or extracted tools root.
    """
    if not isinstance(manifest, dict) or type(manifest.get('schema_version')) is not int or manifest['schema_version'] != 1:
        raise RuntimeError('Unsupported vendor manifest schema')
    payloads = manifest.get('payloads')
    if not isinstance(payloads, list) or not payloads:
        raise RuntimeError('Manifest requires a nonempty payload list')
    lines = ['# vim-config payloads v1',
             '# id\tplatform\tarchive\tsha256\tdestination\tstrip_components']
    identifiers = set()
    archives = set()
    token = re.compile(r'[A-Za-z0-9][A-Za-z0-9._-]*\Z')
    for payload in payloads:
        if not isinstance(payload, dict):
            raise RuntimeError('Payload entries must be objects')
        ident = payload.get('id')
        platform = payload.get('platform')
        parts = payload.get('parts')
        digest = payload.get('sha256')
        destination = payload.get('destination')
        strip = payload.get('strip_components')
        if not isinstance(ident, str) or not token.fullmatch(ident) or ident in identifiers:
            raise RuntimeError('Unsafe or duplicate payload identifier: ' + repr(ident))
        if platform not in ('all', 'darwin-arm64', 'linux-x86_64'):
            raise RuntimeError('Unsupported payload platform: ' + repr(platform))
        if not isinstance(parts, list) or len(parts) != 1 or not isinstance(parts[0], str):
            raise RuntimeError('Bash setup requires exactly one archive per payload: ' + ident)
        archive_name = parts[0]
        components = archive_name.split('/')
        if len(components) < 2 or components[0] != 'payloads' or not archive_name.endswith('.tar.gz') or not all(token.fullmatch(part) and part not in ('.', '..') for part in components) or archive_name in archives:
            raise RuntimeError('Unsafe, unsupported, or duplicate payload archive: ' + repr(archive_name))
        if not isinstance(digest, str) or not re.fullmatch(r'[0-9a-f]{64}', digest):
            raise RuntimeError('Payload SHA256 must contain 64 lowercase hex characters: ' + ident)
        expected_root = 'shared' if platform == 'all' else platform
        if not isinstance(destination, str) or destination.split('/')[0] != expected_root or not all(token.fullmatch(part) and part not in ('.', '..') for part in destination.split('/')):
            raise RuntimeError('Unsafe or platform-mismatched payload destination: ' + repr(destination))
        if type(strip) is not int or not 0 <= strip <= 99:
            raise RuntimeError('Payload strip_components must be an integer between 0 and 99: ' + ident)
        if type(payload.get('size_bytes')) is not int or payload['size_bytes'] <= 0:
            raise RuntimeError('Payload size_bytes must be a positive integer: ' + ident)
        identifiers.add(ident)
        archives.add(archive_name)
        lines.append('\t'.join([ident, platform, archive_name, digest, destination, str(strip)]))
    return ('\n'.join(lines) + '\n').encode('ascii')


def write_payloads_tsv(manifest):
    PAYLOADS_TSV.write_bytes(payloads_tsv(manifest))


def sha256(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def download(url, target, expected=None):
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists() or (expected and sha256(target) != expected):
        temporary = target.with_suffix(target.suffix + '.partial')
        subprocess.run(['curl', '-fsSL', '--retry', '2', url, '-o', str(temporary)], check=True)
        if expected and sha256(temporary) != expected:
            temporary.unlink()
            raise RuntimeError('Checksum mismatch: ' + url)
        temporary.replace(target)
    return target


def extract(archive, destination, strip=0, allow_internal_symlinks=False):
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive, 'r:*') as bundle:
        for member in bundle:
            parts = Path(member.name).parts[strip:]
            if not parts:
                continue
            if member.name.startswith('/') or '..' in parts:
                raise RuntimeError('Unsafe archive path: ' + member.name)
            member.name = str(Path(*parts))
            if member.issym() and allow_internal_symlinks:
                target = posixpath.normpath(posixpath.join(posixpath.dirname(member.name), member.linkname))
                if member.linkname.startswith('/') or target == '..' or target.startswith('../'):
                    raise RuntimeError('Escaping archive symlink: ' + member.name)
                bundle.extract(member, destination)
                continue
            if member.issym() or member.islnk():
                raise RuntimeError('Unexpected source archive link: ' + member.name)
            if member.isdir() or member.isfile():
                bundle.extract(member, destination)


def archive(directory, target):
    with target.open('wb') as raw:
        with gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0, compresslevel=9) as compressed:
            with tarfile.open(fileobj=compressed, mode='w') as bundle:
                for path in sorted(directory.rglob('*')):
                    if path.is_dir():
                        continue
                    info = bundle.gettarinfo(str(path), arcname=path.relative_to(directory).as_posix())
                    info.uid = info.gid = 0
                    info.uname = info.gname = ''
                    info.mtime = 0
                    if path.is_symlink():
                        bundle.addfile(info)
                    else:
                        with path.open('rb') as stream:
                            bundle.addfile(info, stream)


def deb_data(archive_path):
    """Read Debian's ar container without requiring dpkg or ar on the builder."""
    with archive_path.open('rb') as stream:
        if stream.read(8) != b'!<arch>\n':
            raise RuntimeError('Not a Debian ar archive: ' + str(archive_path))
        while True:
            header = stream.read(60)
            if not header:
                break
            if len(header) != 60 or header[58:] != b'`\n':
                raise RuntimeError('Invalid Debian ar member')
            name = header[:16].decode('ascii').strip().rstrip('/')
            size = int(header[48:58])
            data = stream.read(size)
            if size % 2:
                stream.read(1)
            if name.startswith('data.tar'):
                return data
    raise RuntimeError('Missing Debian data archive: ' + str(archive_path))


def prepare_linux_node_runtime(node, work, manifest):
    runtime = manifest['linux_node_runtime']
    (node / 'bin/node').replace(node / 'bin/node.real')
    for item in runtime['packages']:
        source = download(item['url'], work / 'downloads' / item['url'].rsplit('/', 1)[1], item['sha256'])
        with tarfile.open(fileobj=io.BytesIO(deb_data(source)), mode='r:*') as package:
            for member in item['members']:
                info = package.getmember(member['source'])
                if not info.isfile():
                    raise RuntimeError('Expected regular runtime member: ' + member['source'])
                output = node / member['destination']
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_bytes(package.extractfile(info).read())
                output.chmod(info.mode)
    for item in runtime['license_sources']:
        download(item['url'], node / 'licenses/gcc-runtime' / item['name'], item['sha256'])
    (node / 'bin/node').write_text('''#!/bin/sh
# Select only this process's checked-in C++ runtime; no host installation needed.
set -eu
node_runtime=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
LD_LIBRARY_PATH="$node_runtime/lib/node${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH
exec "$node_runtime/bin/node.real" "$@"
''')
    (node / 'bin/node').chmod(0o755)
    notices = ROOT / 'vendor/licenses/gcc-runtime'
    notices.mkdir(parents=True, exist_ok=True)
    for source in (node / 'licenses/gcc-runtime').iterdir():
        shutil.copyfile(source, notices / source.name)


def notices_from_tar(source, destination):
    """Keep notices at every depth, including ring's third-party notices."""
    found = []
    with tarfile.open(source, 'r:*') as bundle:
        for member in bundle:
            relative = Path(*Path(member.name).parts[1:])
            if not member.isfile() or not relative.parts or '..' in relative.parts:
                continue
            name = relative.name.lower()
            if any(any(token in p.lower() for token in ('license', 'licence', 'notice', 'copying', 'copyright', 'authors')) for p in relative.parts) or name in ('cargo.toml',):
                output = destination / relative
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_bytes(bundle.extractfile(member).read())
                found.append(str(relative))
    return found


def collect_licenses(work):
    licenses = ROOT / 'vendor/licenses'
    licenses.mkdir(parents=True, exist_ok=True)
    download('https://raw.githubusercontent.com/PHPantom-dev/phpantom_lsp/0.11.1/LICENSE', licenses / 'phpantom-MIT.txt')
    lock = download('https://raw.githubusercontent.com/PHPantom-dev/phpantom_lsp/0.11.1/Cargo.lock', licenses / 'phpantom-Cargo.lock')
    download('https://raw.githubusercontent.com/PHPantom-dev/phpantom_lsp/0.11.1/stubs.lock', licenses / 'phpantom-stubs.lock')
    download('https://raw.githubusercontent.com/JetBrains/phpstorm-stubs/5f68c1021badebe34119fb8fa10ba7cc25de6c0c/LICENSE', licenses / 'phpstorm-stubs-Apache-2.0.txt')
    download('https://raw.githubusercontent.com/vim/vim/v9.1.1244/runtime/doc/uganda.txt', licenses / 'vim-license.txt')
    crates = []
    for block in lock.read_text().split('[[package]]')[1:]:
        if 'source = "registry+' not in block:
            continue
        get = lambda key: re.search(r'^' + key + r' = "([^"]+)"', block, re.M).group(1)
        crates.append(dict(name=get('name'), version=get('version'), sha256=get('checksum')))
    def crate_notices(item):
        name, version = item['name'], item['version']
        url = f'https://static.crates.io/crates/{name}/{name}-{version}.crate'
        source = download(url, work / 'crate-downloads' / f'{name}-{version}.crate', item['sha256'])
        item['source'] = url
        item['notice_files'] = notices_from_tar(source, licenses / 'phpantom-dependencies' / f'{name}-{version}')
        return item
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        crates = list(pool.map(crate_notices, crates))
    (licenses / 'phpantom-dependencies.json').write_text(json.dumps(crates, indent=2) + '\n')
    # Some workspace crates omit their inherited licence files from the crate
    # archive. Recover the notices from the exact VCS revision embedded by Cargo.
    upstream = []
    trees = {}
    for item in crates:
        if any('license' in name.lower() or 'copying' in name.lower() or 'notice' in name.lower() for name in item['notice_files']) or any('permission is hereby granted' in (licenses / 'phpantom-dependencies' / (item['name'] + '-' + item['version']) / name).read_text(errors='replace').lower() for name in item['notice_files']):
            continue
        name = item['name'] + '-' + item['version']
        cargo = (licenses / 'phpantom-dependencies' / name / 'Cargo.toml').read_text()
        repository = re.search(r'^repository\s*=\s*"([^"]+)"', cargo, re.M).group(1).removesuffix('.git')
        with tarfile.open(work / 'crate-downloads' / (name + '.crate')) as source:
            vcs = json.load(source.extractfile(name + '/.cargo_vcs_info.json'))
        revision = vcs['git']['sha1']
        repo = repository.removeprefix('https://github.com/')
        if (repo, revision) not in trees:
            tree = download('https://api.github.com/repos/' + repo + '/git/trees/' + revision + '?recursive=1', work / 'notice-trees' / (repo.replace('/', '-') + '-' + revision + '.json'))
            trees[(repo, revision)] = json.loads(tree.read_text())['tree']
        files = []
        for entry in trees[(repo, revision)]:
            parts = Path(entry['path']).parts
            if entry['type'] != 'blob' or not any(any(token in p.lower() for token in ('license', 'licence', 'notice', 'copying', 'copyright')) for p in parts):
                continue
            target = licenses / 'phpantom-upstream' / (repo.replace('/', '-') + '-' + revision) / entry['path']
            download('https://raw.githubusercontent.com/' + repo + '/' + revision + '/' + entry['path'], target)
            files.append(str(target.relative_to(licenses)))
        if not files:
            raise RuntimeError('No inherited licence notices found for ' + name)
        upstream.append(dict(crate=name, repository=repository, revision=revision, notice_files=files))
    (licenses / 'phpantom-upstream-sources.json').write_text(json.dumps(upstream, indent=2) + '\n')
    for source in sorted((work / 'gomodcache').glob('**/go.mod')):
        directory = source.parent
        if not any('@' in p for p in directory.parts):
            continue
        relative = directory.relative_to(work / 'gomodcache')
        for path in directory.rglob('*'):
            if path.is_file() and any(token in path.name.lower() for token in ('license', 'licence', 'notice', 'copying', 'copyright', 'patents')):
                destination = licenses / 'gopls-dependencies' / relative / path.relative_to(directory)
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, destination)
    for name in ('LICENSE', 'PATENTS'):
        source = work / 'go-host/go' / name
        if source.exists():
            shutil.copyfile(source, licenses / ('go-' + name + '.txt'))
    node_license = work / 'node-darwin-arm64/licenses/node/LICENSE'
    if node_license.exists():
        shutil.copyfile(node_license, licenses / 'node-LICENSE.txt')
    js = work / 'js/node_modules'
    packages = []
    for package in sorted(js.glob('**/package.json')):
        directory = package.parent
        if directory.parent.name != 'node_modules' and directory.parent.parent.name != 'node_modules':
            continue
        data = json.loads(package.read_text())
        packages.append(dict(name=data.get('name'), version=data.get('version'), license=data.get('license'), path=str(directory.relative_to(js))))
        for path in directory.rglob('*'):
            if path.is_file() and any(token in path.name.lower() for token in ('license', 'licence', 'notice', 'copying', 'copyright')):
                output = licenses / 'javascript-dependencies' / path.relative_to(js)
                output.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, output)
    (licenses / 'javascript-dependencies.json').write_text(json.dumps(packages, indent=2) + '\n')
    print(f'Preserved notices for {len(crates)} locked Rust crates and {len(packages)} JavaScript packages')


def supported_host():
    identity = (os.uname().sysname, os.uname().machine)
    if identity == ('Darwin', 'arm64'):
        return 'darwin-arm64'
    if identity[0] == 'Linux' and identity[1] in ('x86_64', 'amd64'):
        return 'linux-x86_64'
    raise RuntimeError('Unsupported preparation host: ' + repr(identity))


def record_payloads(manifest, identifiers=None):
    for payload in manifest['payloads']:
        if identifiers is not None and payload['id'] not in identifiers:
            continue
        payload['sha256'] = sha256(ROOT / payload['parts'][0])
        payload['size_bytes'] = (ROOT / payload['parts'][0]).stat().st_size
    MANIFEST.write_text(json.dumps(manifest, indent=2) + '\n')
    write_payloads_tsv(manifest)


def go_preparation_environment(work, manifest, offline=False):
    """Use the checked-in SDK and task-local caches, with telemetry disabled."""
    work.mkdir(parents=True, exist_ok=True)
    host = supported_host()
    sdk = next(p for p in manifest['payloads'] if p['platform'] == host and p['id'].startswith('go1.'))
    sdk_archive = ROOT / sdk['parts'][0]
    if sha256(sdk_archive) != sdk['sha256']:
        raise RuntimeError('Go SDK archive checksum mismatch')
    host_go = work / 'go-host'
    extract(sdk_archive, host_go)
    go = str(host_go / 'go/bin/go')
    build_config = work / 'config'
    telemetry_mode = build_config / 'go/telemetry/mode'
    telemetry_mode.parent.mkdir(parents=True, exist_ok=True)
    telemetry_mode.write_text('off\n')
    telemetry_mode.chmod(0o600)
    env = os.environ.copy()
    # All required Go paths are explicit. Linux reads the supported off mode
    # above; Darwin ignores XDG_CONFIG_HOME, so remove inherited HOME to make
    # os.UserConfigDir fail and telemetry default off without touching the host.
    env.pop('HOME', None)
    env.update(GOPATH=str(work / 'gopath'), GOMODCACHE=str(work / 'gomodcache'), GOCACHE=str(work / 'go-cache'), XDG_CONFIG_HOME=str(build_config), GOENV='off', GOTOOLCHAIN='local', CGO_ENABLED='0', GOFLAGS='')
    if offline:
        env.update(GOPROXY='off', GOSUMDB='off')
    if subprocess.check_output([go, 'env', 'GOTELEMETRY'], env=env, text=True).strip() != 'off':
        raise RuntimeError('Go preparation telemetry is not disabled')
    return go, env


def build_affinity_helper(work, manifest, offline=False):
    config = manifest['affinity_exec_build']
    source = ROOT / config['source_file']
    if sha256(source) != config['source_sha256']:
        raise RuntimeError('affinity-exec source checksum mismatch')
    go, env = go_preparation_environment(work, manifest, offline)
    env.update(GOOS='linux', GOARCH='amd64')
    directory = work / 'affinity-build/linux-x86_64'
    output = directory / 'bin/affinity-exec'
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([go, 'build', *config['flags'], '-o', str(output), str(source)], env=env, check=True)
    output.chmod(0o755)
    notices = directory / 'licenses/affinity-exec'
    notices.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / 'tools/affinity-exec.LICENSE', notices / 'MIT.txt')
    for name in ('LICENSE', 'PATENTS'):
        shutil.copyfile(work / 'go-host/go' / name, notices / ('Go-' + name))
    payload = next(p for p in manifest['payloads'] if p['id'] == config['payload_id'])
    archive(directory, ROOT / payload['parts'][0])


def build_gopls(work, manifest, offline=False):
    """Build only the patched Go server; never mutate the module source cache."""
    go, env = go_preparation_environment(work, manifest, offline)
    config = manifest['gopls_build']
    patcher = ROOT / config['patch_script']
    if sha256(patcher) != config['patch_script_sha256']:
        raise RuntimeError('gopls patch helper checksum mismatch')
    module = config['module'] + '@' + config['version']
    info = json.loads(subprocess.check_output([go, 'mod', 'download', '-json', module], env=env))
    if info['Sum'] != config['module_sum']:
        raise RuntimeError('gopls module checksum changed')
    source = work / 'gopls-source'
    if source.exists():
        # Module-cache directories are read-only. Change only the temporary
        # source copy, including an earlier copy left by a previous build.
        for directory in [source, *source.rglob('*')]:
            if directory.is_dir() and not directory.is_symlink():
                directory.chmod(directory.stat().st_mode | 0o200)
        shutil.rmtree(source)
    shutil.copytree(info['Dir'], source)
    for directory in [source, *source.rglob('*')]:
        if directory.is_dir() and not directory.is_symlink():
            directory.chmod(directory.stat().st_mode | 0o200)
    if sha256(source / config['source_file']) != config['source_file_sha256']:
        raise RuntimeError('gopls upstream file checksum mismatch')
    dependency = config['gocommand_dependency']
    dependency_module = dependency['module'] + '@' + dependency['version']
    dependency_info = json.loads(subprocess.check_output([go, 'mod', 'download', '-json', dependency_module], env=env))
    if dependency_info['Sum'] != dependency['module_sum']:
        raise RuntimeError('x/tools dependency module checksum changed')
    dependency_file = Path(dependency_info['Dir']) / dependency['source_file']
    if sha256(dependency_file) != dependency['source_file_sha256']:
        raise RuntimeError('x/tools gocommand upstream file checksum mismatch')
    dependency_source = work / 'gopls-tools-source'
    if dependency_source.exists():
        for directory in [dependency_source, *dependency_source.rglob('*')]:
            if directory.is_dir() and not directory.is_symlink():
                directory.chmod(directory.stat().st_mode | 0o200)
        shutil.rmtree(dependency_source)
    shutil.copytree(dependency_info['Dir'], dependency_source)
    for directory in [dependency_source, *dependency_source.rglob('*')]:
        if directory.is_dir() and not directory.is_symlink():
            directory.chmod(directory.stat().st_mode | 0o200)
    patched_dependency_file = dependency_source / dependency['source_file']
    subprocess.run([os.sys.executable, str(patcher), str(source), '--gocommand-file', str(patched_dependency_file)], check=True)
    if sha256(source / config['source_file']) != config['patched_file_sha256']:
        raise RuntimeError('gopls patched file checksum mismatch')
    if sha256(patched_dependency_file) != dependency['patched_file_sha256']:
        raise RuntimeError('x/tools gocommand patched file checksum mismatch')
    # Go deliberately refuses overlays beneath GOMODCACHE. Only this writable
    # gopls source copy gets a replace directive pointing at the verified copy.
    go_mod = source / 'go.mod'
    go_mod.chmod(go_mod.stat().st_mode | 0o200)
    subprocess.run([go, 'mod', 'edit', '-replace=' + dependency['module'] + '=' + str(dependency_source)], cwd=source, env=env, check=True)
    for osname, arch, platform in [('darwin', 'arm64', 'darwin-arm64'), ('linux', 'amd64', 'linux-x86_64')]:
        output = work / 'gopls-build' / platform / 'bin/gopls'
        output.parent.mkdir(parents=True, exist_ok=True)
        env.update(GOOS=osname, GOARCH=arch)
        subprocess.run([go, 'build', *config['flags'], '-o', str(output), '.'], cwd=source, env=env, check=True)
        output.chmod(0o755)
        marker = output.parent / 'gopls-low-resource'
        marker.write_text(config['output_version'] + '\n')
        marker.chmod(0o644)
    for platform in ('darwin-arm64', 'linux-x86_64'):
        payload = next(p for p in manifest['payloads'] if p['platform'] == platform and p['id'].startswith('gopls-'))
        archive(work / 'gopls-build' / platform, ROOT / payload['parts'][0])


def patch_javascript(directory, manifest):
    config = manifest['typescript_shutdown_patch']
    patcher = ROOT / config['patch_script']
    if sha256(patcher) != config['patch_script_sha256']:
        raise RuntimeError('TypeScript shutdown patch helper checksum mismatch')
    target = directory / config['source_file']
    subprocess.run([os.sys.executable, str(patcher), str(target)], check=True)
    if sha256(target) != config['patched_file_sha256']:
        raise RuntimeError('TypeScript shutdown patched file checksum mismatch')


def rebuild_javascript(work, manifest):
    """Repack the verified existing JS bundle; no npm, downloads or compiler."""
    config = manifest['typescript_shutdown_patch']
    payload = next(p for p in manifest['payloads'] if p['id'] == config['payload_id'])
    source = ROOT / payload['parts'][0]
    if sha256(source) != payload['sha256']:
        raise RuntimeError('Existing JavaScript archive checksum mismatch')
    directory = work / 'javascript-repack'
    if directory.exists():
        shutil.rmtree(directory)
    extract(source, directory, allow_internal_symlinks=True)
    patch_javascript(directory, manifest)
    archive(directory, source)


def rebuild(work, manifest):
    work.mkdir(parents=True, exist_ok=True)
    downloads = work / 'downloads'
    sources = {}
    for item in manifest['sources']:
        filename = item['url'].rsplit('/', 1)[1]
        source = download(item['url'], downloads / filename, item['sha256'])
        sources[(item['name'], item['platform'])] = source
        if item['name'] in ('go', 'phpantom'):
            payload = next(p for p in manifest['payloads'] if p['platform'] == item['platform'] and p['id'].startswith('go1.' if item['name'] == 'go' else 'phpantom'))
            shutil.copyfile(source, ROOT / payload['parts'][0])
    for item in manifest['plugins']:
        source = download(item['archive_source'], downloads / (item['name'] + '.tar.gz'), item['archive_sha256'])
        destination = ROOT / item['path']
        if destination.exists():
            shutil.rmtree(destination)
        extract(source, destination, strip=1)
    patcher = ROOT / 'tools/patch-lsp.py'
    if patcher.exists():
        subprocess.run([os.sys.executable, str(patcher)], cwd=ROOT, check=True)
    for platform, suffix in [('linux-x86_64', 'linux-x64'), ('darwin-arm64', 'darwin-arm64')]:
        node = work / ('node-' + platform)
        node.mkdir(exist_ok=True)
        with tarfile.open(sources[('node', platform)]) as bundle:
            prefix = 'node-v' + manifest['versions']['node'] + '-' + suffix + '/'
            for member_name, target in [('bin/node', 'bin/node'), ('LICENSE', 'licenses/node/LICENSE')]:
                member = bundle.getmember(prefix + member_name)
                output = node / target
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_bytes(bundle.extractfile(member).read())
                output.chmod(member.mode)
        if platform == 'linux-x86_64':
            prepare_linux_node_runtime(node, work, manifest)
        archive(node, ROOT / 'payloads' / ('node-v' + manifest['versions']['node'] + '-' + platform + '.tar.gz'))
    js = work / 'js'
    js.mkdir(exist_ok=True)
    for name in ('package.json', 'package-lock.json'):
        shutil.copyfile(ROOT / 'vendor/js' / name, js / name)
    env = os.environ.copy()
    env['NPM_CONFIG_CACHE'] = str(work / 'npm-cache')
    subprocess.run(['npm', 'ci', '--prefix', str(js), '--ignore-scripts', '--omit=dev', '--no-audit', '--no-fund'], env=env, check=True)
    shutil.rmtree(js / 'node_modules/.bin', ignore_errors=True)
    patch_javascript(js, manifest)
    archive(js, ROOT / 'payloads/javascript-language-servers.tar.gz')
    build_gopls(work, manifest)
    build_affinity_helper(work, manifest)
    subprocess.run([os.sys.executable, str(ROOT / 'tools/build-phpantom.py'), '--work-dir', str(work / 'phpantom'), '--defer-manifest'], check=True)
    collect_licenses(work)
    record_payloads(manifest)
    print('Rebuilt offline payloads; review the manifest and archive changes before publication.')


def verify(manifest):
    expected_tsv = payloads_tsv(manifest)
    if not PAYLOADS_TSV.exists() or PAYLOADS_TSV.read_bytes() != expected_tsv:
        raise RuntimeError('tools/payloads.tsv differs from the JSON manifest; run tools/prepare-bundle.py --write-payloads-tsv')
    patch = manifest['gopls_build']
    if sha256(ROOT / patch['patch_script']) != patch['patch_script_sha256']:
        raise RuntimeError('gopls patch helper checksum mismatch')
    helper = manifest['affinity_exec_build']
    if sha256(ROOT / helper['source_file']) != helper['source_sha256']:
        raise RuntimeError('affinity-exec source checksum mismatch')
    typescript = manifest['typescript_shutdown_patch']
    if sha256(ROOT / typescript['patch_script']) != typescript['patch_script_sha256']:
        raise RuntimeError('TypeScript shutdown patch helper checksum mismatch')
    php = manifest['phpantom_build']
    if sha256(ROOT / php['patch_script']) != php['patch_script_sha256'] or sha256(ROOT / php['build_script']) != php['build_script_sha256']:
        raise RuntimeError('PHPantom preparation or patch helper checksum mismatch')
    total = 0
    for payload in manifest['payloads']:
        digest = hashlib.sha256()
        size = 0
        for name in payload['parts']:
            path = ROOT / name
            if path.stat().st_size >= 90 * 1024 * 1024:
                raise RuntimeError('Archive part exceeds repository limit: ' + name)
            with path.open('rb') as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(chunk)
                    size += len(chunk)
        if digest.hexdigest() != payload['sha256'] or size != payload['size_bytes']:
            raise RuntimeError('Payload checksum or size mismatch: ' + payload['id'])
        total += size
    for item in manifest['plugins']:
        if not (ROOT / item['path']).is_dir():
            raise RuntimeError('Missing plugin: ' + item['path'])
    print(f'OK: {len(manifest["payloads"])} payloads, {total:,} compressed bytes, {len(manifest["plugins"])} pinned plugins')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_mutually_exclusive_group(required=True)
    actions.add_argument('--verify', action='store_true')
    actions.add_argument('--rebuild', action='store_true')
    actions.add_argument('--rebuild-gopls', action='store_true', help='rebuild only the two patched gopls archives, leaving other payloads and Vim sources unchanged')
    actions.add_argument('--rebuild-affinity', action='store_true', help='rebuild only the small Linux CPU-affinity launcher payload')
    actions.add_argument('--rebuild-javascript', action='store_true', help='repack only the verified JavaScript archive with the pinned shutdown patch; no npm, downloads or compilation')
    actions.add_argument('--rebuild-phpantom', action='store_true', help='prepare the patched static Linux PHP server using pinned Rust/Zig inputs on macOS arm64')
    actions.add_argument('--write-payloads-tsv', action='store_true', help='regenerate the Bash-readable payload table from the JSON manifest, without downloads')
    actions.add_argument('--collect-licenses', action='store_true', help=argparse.SUPPRESS)
    parser.add_argument('--work-dir', type=Path)
    parser.add_argument('--offline', action='store_true', help='with a partial rebuild, use only checked-in payloads and prepared task-local caches')
    args = parser.parse_args()
    if args.offline and not (args.rebuild_gopls or args.rebuild_affinity or args.rebuild_javascript or args.rebuild_phpantom):
        parser.error('--offline is supported only with a partial rebuild')
    manifest = json.loads(MANIFEST.read_text())
    payloads_tsv(manifest)  # Reject unsupported or unsafe rows before mutation.
    if args.write_payloads_tsv:
        write_payloads_tsv(manifest)
    elif args.verify:
        verify(manifest)
    else:
        work = args.work_dir or Path(tempfile.mkdtemp(prefix='vim-config-bundle-'))
        if args.rebuild_phpantom:
            subprocess.run([os.sys.executable, str(ROOT / 'tools/build-phpantom.py'), '--work-dir', str(work)] + (['--offline'] if args.offline else []), check=True)
        elif args.rebuild_javascript:
            rebuild_javascript(work, manifest)
            record_payloads(manifest, {manifest['typescript_shutdown_patch']['payload_id']})
            verify(manifest)
            print('Repacked only the JavaScript archive with its pinned shutdown patch.')
        elif args.rebuild_affinity:
            build_affinity_helper(work, manifest, offline=args.offline)
            record_payloads(manifest, {manifest['affinity_exec_build']['payload_id']})
            verify(manifest)
            print('Rebuilt only the Linux CPU-affinity launcher archive.')
        elif args.rebuild_gopls:
            build_gopls(work, manifest, offline=args.offline)
            record_payloads(manifest, {p['id'] for p in manifest['payloads'] if p['id'].startswith('gopls-')})
            verify(manifest)
            print('Rebuilt the two patched gopls archives; all other payloads were left untouched.')
        elif args.collect_licenses:
            collect_licenses(work)
        else:
            rebuild(work, manifest)


if __name__ == '__main__':
    main()
