#!/usr/bin/env python3
"""Maintainer-only static Linux PHPantom build on macOS arm64.

All source, compiler, target-library and linker archives are pinned by checksum.
Targets only unpack the resulting payload; they do not run this script.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('bundle_helpers', ROOT / 'tools/prepare-bundle.py')
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)


def fetch(item, work, offline):
    path = work / 'downloads' / item['filename']
    if offline and (not path.exists() or helpers.sha256(path) != item['sha256']):
        raise RuntimeError('Missing or changed offline build input: ' + str(path))
    return helpers.download(item['url'], path, item['sha256'])


def prepare(work, config, offline):
    if helpers.supported_host() != 'darwin-arm64':
        raise RuntimeError('This pinned cross-build recipe requires a macOS arm64 preparation host')
    for item in config['preparation_archives']:
        source = fetch(item, work, offline)
        destination = work / item['extract_directory']
        if destination.exists():
            shutil.rmtree(destination)
        helpers.extract(source, destination, allow_internal_symlinks=True)
    toolchain = work / 'toolchain'
    if toolchain.exists():
        shutil.rmtree(toolchain)
    for item in config['preparation_archives']:
        if item.get('component'):
            shutil.copytree(work / item['extract_directory'] / item['component'], toolchain,
                            dirs_exist_ok=True, symlinks=True)
    source = work / 'source'
    if source.exists():
        shutil.rmtree(source)
    helpers.extract(fetch(config['source_archive'], work, offline), source, strip=1)
    lock = source / 'Cargo.lock'
    if helpers.sha256(lock) != config['cargo_lock_sha256']:
        raise RuntimeError('Pinned PHPantom Cargo.lock checksum changed')
    vendor = work / 'vendor'
    if vendor.exists():
        shutil.rmtree(vendor)
    vendor.mkdir(parents=True)
    for block in lock.read_text().split('[[package]]')[1:]:
        if 'source = "registry+' not in block:
            continue
        get = lambda key: re.search(r'^' + key + r' = "([^"]+)"', block, re.M).group(1)
        name, version, digest = get('name'), get('version'), get('checksum')
        filename = name + '-' + version + '.crate'
        item = {'filename': 'crates/' + filename, 'sha256': digest,
                'url': 'https://static.crates.io/crates/' + name + '/' + filename}
        helpers.extract(fetch(item, work, offline), vendor)
        directory = vendor / (name + '-' + version)
        files = {p.relative_to(directory).as_posix(): helpers.sha256(p)
                 for p in directory.rglob('*') if p.is_file() and p.name != '.cargo-checksum.json'}
        (directory / '.cargo-checksum.json').write_text(json.dumps({'files': files, 'package': digest}, sort_keys=True))
    stubs = source / 'stubs/jetbrains/phpstorm-stubs'
    helpers.extract(fetch(config['stubs_archive'], work, offline), stubs, strip=1)
    (stubs / '.commit').write_text(config['stubs_revision'] + '\n')
    subprocess.run([os.sys.executable, str(ROOT / config['patch_script']), str(source / 'src/main.rs')], check=True)
    if helpers.sha256(source / 'src/main.rs') != config['patched_file_sha256']:
        raise RuntimeError('PHPantom patched main.rs checksum mismatch')
    (source / '.cargo').mkdir(exist_ok=True)
    (source / '.cargo/config.toml').write_text(
        '[source.crates-io]\nreplace-with = "vendored-sources"\n'
        '[source.vendored-sources]\ndirectory = ' + json.dumps(str(vendor)) + '\n'
        '[target.x86_64-unknown-linux-musl]\nlinker = ' + json.dumps(str(work / 'zig-cc')) + '\n')


def build(work, config):
    source = work / 'source'
    if helpers.sha256(source / 'Cargo.lock') != config['cargo_lock_sha256'] or helpers.sha256(source / 'src/main.rs') != config['patched_file_sha256']:
        raise RuntimeError('Prepared PHP source checksums do not match the manifest')
    if (source / 'stubs/jetbrains/phpstorm-stubs/.commit').read_text().strip() != config['stubs_revision']:
        raise RuntimeError('Prepared PHP built-in stubs revision changed')
    cargo = shutil.which('cargo')
    if not cargo or not subprocess.check_output([cargo, '--version'], text=True).startswith('cargo ' + config['rust_version'] + ' '):
        raise RuntimeError('Preparation requires Cargo ' + config['rust_version'])
    zig = work / config['zig_executable']
    cc = work / 'zig-cc'
    cc.write_text('''#!/usr/bin/env python3
import os, sys
args = [arg.replace('x86_64-unknown-linux-musl', 'x86_64-linux-musl') if arg.startswith('--target=') or arg == 'x86_64-unknown-linux-musl' else arg for arg in sys.argv[1:]]
os.execv(''' + repr(str(zig)) + ''', ['zig', 'cc', '-target', 'x86_64-linux-musl', *args])
''')
    cc.chmod(0o755)
    ar = work / 'zig-ar'
    ar.write_text('#!/usr/bin/env python3\nimport os,sys\nos.execv(' + repr(str(zig)) + ", ['zig', 'ar', *sys.argv[1:]])\n")
    ar.chmod(0o755)
    env = os.environ.copy()
    env.update(CARGO_HOME=str(work / 'cargo-home'), CARGO_TARGET_DIR=str(work / 'target'),
               RUSTC=str(work / 'toolchain/bin/rustc'), CC_x86_64_unknown_linux_musl=str(cc),
               AR_x86_64_unknown_linux_musl=str(ar), CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER=str(cc),
               CARGO_PROFILE_RELEASE_LTO='thin', CARGO_PROFILE_RELEASE_STRIP='symbols',
               CARGO_BUILD_JOBS='6', PHPANTOM_GIT_VERSION=config['output_version'],
               SDKROOT=config['macos_sdk'], ZIG_GLOBAL_CACHE_DIR=str(work / 'zig-global-cache'),
               ZIG_LOCAL_CACHE_DIR=str(work / 'zig-local-cache'),
               RUSTFLAGS='--remap-path-prefix=' + str(work) + '=/vim-config/phpantom-build -C link-self-contained=no')
    subprocess.run([cargo, 'build', '--locked', '--offline', '--release', '--target',
                    'x86_64-unknown-linux-musl', '--features', 'offline-stubs', '--bin', 'phpantom_lsp'],
                   cwd=source, env=env, check=True)
    outputs = list((work / 'target/x86_64-unknown-linux-musl/release/build').glob('phpantom_lsp-*/output'))
    if not outputs or not any('PHPANTOM_STUBS_VERSION=master@' + config['stubs_revision'][:10] in p.read_text() for p in outputs):
        raise RuntimeError('Build did not confirm embedding the pinned PHP standard-library stubs')
    output = work / 'target/x86_64-unknown-linux-musl/release/phpantom_lsp'
    directory = work / 'payload'
    directory.mkdir(exist_ok=True)
    shutil.copyfile(output, directory / 'phpantom_lsp')
    (directory / 'phpantom_lsp').chmod(0o755)
    (directory / 'phpantom-low-resource').write_text(config['output_version'] + '\n')
    notices = ROOT / 'vendor/licenses/phpantom-runtime'
    rust_notices = notices / 'rust'
    rust_notices.mkdir(parents=True, exist_ok=True)
    rust_docs = work / 'toolchain/share/doc/rust'
    shutil.copyfile(rust_docs / 'COPYRIGHT-library.html', rust_notices / 'COPYRIGHT-library.html')
    shutil.copytree(rust_docs / 'licenses', rust_notices / 'licenses', dirs_exist_ok=True)
    zig_root = zig.parent
    shutil.copyfile(zig_root / 'lib/libc/musl/COPYRIGHT', notices / 'musl-COPYRIGHT')
    shutil.copyfile(zig_root / 'lib/libunwind/LICENSE.TXT', notices / 'libunwind-LICENSE.txt')
    return directory


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work-dir', type=Path, required=True)
    parser.add_argument('--offline', action='store_true')
    parser.add_argument('--prepared', action='store_true', help='use an already prepared task-local toolchain and checksum-verified source tree')
    parser.add_argument('--defer-manifest', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    manifest = json.loads((ROOT / 'tools/vendor-manifest.json').read_text())
    config = manifest['phpantom_build']
    if helpers.sha256(ROOT / config['patch_script']) != config['patch_script_sha256']:
        raise RuntimeError('PHPantom patch helper checksum mismatch')
    work = args.work_dir.resolve()
    work.mkdir(parents=True, exist_ok=True)
    if not args.prepared:
        prepare(work, config, args.offline)
    directory = build(work, config)
    payload = next(p for p in manifest['payloads'] if p['id'] == config['payload_id'])
    helpers.archive(directory, ROOT / payload['parts'][0])
    if not args.defer_manifest:
        helpers.record_payloads(manifest, {config['payload_id']})
        helpers.verify(manifest)


if __name__ == '__main__':
    main()
