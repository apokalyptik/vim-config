#!/bin/sh
# Linux isolation integration test in a disposable RAM-only guest. No network.
# Usage: tests/qemu-helper.sh KERNEL BUSYBOX DEBIAN-PACKAGES-JSON DOWNLOADS-DIR
# The JSON records Package/Filename/SHA256 for the Debian util-linux/mount and
# shared-library packages. Set VIM_CONFIG_QEMU_PAYLOADS=1 to additionally stage
# the checked-in Linux PHPantom/Node/gopls archives and test their startup.
# VIM_CONFIG_QEMU_NO_SYSTEM_CXX=1 omits system libstdc++/libgcc to test the
# bundled Node runtime's private C++ libraries.
# VIM_CONFIG_QEMU_GOPLS_NO_PROC=1 adds an offline Go SDK/LSP regression with
# /proc absent. Supply VIM_CONFIG_QEMU_GOPLS_BASELINE (upstream executable), and
# optionally VIM_CONFIG_QEMU_GOPLS_PATCHED to test a build before repackaging.
# VIM_CONFIG_QEMU_GOPLS_RESOURCES=1 also compares cold-cache Go process/thread
# peaks; VIM_CONFIG_QEMU_GOPLS_RESOURCE_BASELINE must name the .1 patched build.
# VIM_CONFIG_QEMU_ADDITIONAL_LSPS=1 adds PHP/TypeScript cold-workspace cases.
# VIM_CONFIG_QEMU_RESOURCE_FAMILIES=typescript (or comma list) focuses reruns.
# VIM_CONFIG_QEMU_RESOURCE_CURRENT_ONLY=1 skips historical baseline cases.
# VIM_CONFIG_QEMU_PHP_PATCHED stages the approved low-resource PHP candidate
# before its archive is repacked (fixture-only version marker is also created).
# Test inputs are explicitly supplied, not host files.
set -eu
[ "$#" -eq 4 ] || { printf '%s\n' 'Usage: tests/qemu-helper.sh KERNEL BUSYBOX DEBIAN-PACKAGES-JSON DOWNLOADS-DIR' >&2; exit 64; }
qemu_test_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
python3 - "$qemu_test_root" "$@" <<'PY'
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys

repo, kernel, busybox, package_manifest, downloads = map(Path, sys.argv[1:])
qemu = shutil.which('qemu-system-x86_64')
tar = shutil.which('bsdtar')
if not qemu or not tar:
    raise SystemExit('qemu-system-x86_64 and bsdtar are required on the test host')
fixture = repo / '.state/qemu-helper'
rootfs = fixture / 'test-rootfs'
if rootfs.exists():
    shutil.rmtree(rootfs)
rootfs.mkdir(parents=True)
for record in json.loads(package_manifest.read_text()):
    if os.environ.get('VIM_CONFIG_QEMU_NO_SYSTEM_CXX') == '1' and record['Package'] in {'libstdc++6', 'libgcc-s1'}:
        continue
    package = downloads / Path(record['Filename']).name
    if hashlib.sha256(package.read_bytes()).hexdigest() != record['SHA256']:
        raise SystemExit('Checksum mismatch: ' + record['Package'])
    members = subprocess.check_output([tar, '-tf', str(package)], text=True).splitlines()
    data_member = next(item for item in members if item.startswith('data.tar.'))
    data = subprocess.check_output([tar, '-xOf', str(package), data_member])
    subprocess.run([tar, '-xf', '-', '-C', str(rootfs)], input=data, check=True)
for directory in ['bin', 'usr/bin', 'etc', 'dev/pts', 'proc', 'sys', 'tmp', 'run',
                  'home/tester/project', 'home/tester/real', 'opt/vim-config/bin',
                  'opt/vim-config/libexec', 'nfs', 'extra deny']:
    (rootfs / directory).mkdir(parents=True, exist_ok=True)
shutil.copy2(busybox, rootfs / 'bin/busybox')
if not (rootfs / 'bin/sh').exists():
    (rootfs / 'bin/sh').symlink_to('busybox')
for relative in ['bin/helper-run', 'libexec/helper-run-inner']:
    shutil.copy2(repo / relative, rootfs / 'opt/vim-config' / relative)
include_resources = os.environ.get('VIM_CONFIG_QEMU_GOPLS_RESOURCES') == '1'
include_additional = include_resources and os.environ.get('VIM_CONFIG_QEMU_ADDITIONAL_LSPS') == '1'
resource_families = os.environ.get('VIM_CONFIG_QEMU_RESOURCE_FAMILIES', '')
resource_current_only = os.environ.get('VIM_CONFIG_QEMU_RESOURCE_CURRENT_ONLY') == '1'
if any(name not in {'go', 'php', 'typescript'} for name in resource_families.split(',') if name):
    raise SystemExit('Resource families must be a comma-separated subset of go,php,typescript')
include_no_proc = os.environ.get('VIM_CONFIG_QEMU_GOPLS_NO_PROC') == '1' or include_resources
run_original_no_proc = include_no_proc and not (include_resources and resource_current_only)
needs_go_sdk = run_original_no_proc or (include_resources and (not resource_families or 'go' in resource_families.split(',')))
include_payloads = os.environ.get('VIM_CONFIG_QEMU_PAYLOADS') == '1' or include_no_proc
if include_payloads:
    manifest = json.loads((repo / 'tools/vendor-manifest.json').read_text())
    for payload in manifest['payloads']:
        shared = include_additional and payload['platform'] == 'all' and payload['id'] == 'javascript-language-servers'
        selected = payload['id'].startswith(('phpantom-', 'node-', 'gopls-', 'affinity-exec-')) or (needs_go_sdk and payload['id'].startswith('go1.'))
        if not shared and (payload['platform'] != 'linux-x86_64' or not selected):
            continue
        if len(payload['parts']) != 1:
            raise SystemExit('This fixture expects a single-part payload archive')
        archive = repo / payload['parts'][0]
        if hashlib.sha256(archive.read_bytes()).hexdigest() != payload['sha256']:
            raise SystemExit('Payload checksum mismatch: ' + payload['id'])
        destination = rootfs / ('opt/vim-config/.state/tools/shared' if shared else 'opt/vim-tools')
        if payload['id'].startswith('phpantom-'):
            destination /= 'bin'
        destination.mkdir(parents=True, exist_ok=True)
        subprocess.run([tar, '-xf', str(archive), '-C', str(destination)], check=True)
    php_candidate = os.environ.get('VIM_CONFIG_QEMU_PHP_PATCHED')
    if php_candidate:
        shutil.copy2(php_candidate, rootfs / 'opt/vim-tools/bin/phpantom_lsp')
        (rootfs / 'opt/vim-tools/bin/phpantom-low-resource').write_text('0.11.1+vim-config.1\n')
if include_no_proc:
    baseline = os.environ.get('VIM_CONFIG_QEMU_GOPLS_BASELINE')
    if run_original_no_proc and not baseline:
        raise SystemExit('VIM_CONFIG_QEMU_GOPLS_BASELINE must name an upstream Linux gopls executable')
    if run_original_no_proc:
        shutil.copy2(baseline, rootfs / 'opt/vim-tools/bin/gopls-upstream')
    candidate = os.environ.get('VIM_CONFIG_QEMU_GOPLS_PATCHED')
    if candidate:
        shutil.copy2(candidate, rootfs / 'opt/vim-tools/bin/gopls')
    shutil.copy2(repo / 'bin/language-server', rootfs / 'opt/vim-config/bin/language-server')
    shutil.copy2(repo / 'libexec/resource-env.sh', rootfs / 'opt/vim-config/libexec/resource-env.sh')
    lifecycle = repo / 'libexec/typescript-lifecycle.cjs'
    if lifecycle.is_file():
        shutil.copy2(lifecycle, rootfs / 'opt/vim-config/libexec/typescript-lifecycle.cjs')
    shutil.copy2(repo / 'tests/gopls-no-proc.cjs', rootfs / 'usr/bin/gopls-no-proc.cjs')
    tool_links = rootfs / 'opt/vim-config/.state/tools'
    tool_links.mkdir(parents=True, exist_ok=True)
    (tool_links / 'linux-x86_64').symlink_to('/opt/vim-tools')
if include_resources:
    baseline = os.environ.get('VIM_CONFIG_QEMU_GOPLS_RESOURCE_BASELINE')
    if not resource_current_only and not baseline:
        raise SystemExit('VIM_CONFIG_QEMU_GOPLS_RESOURCE_BASELINE must name the .1 patched Linux executable')
    if not resource_current_only:
        shutil.copy2(baseline, rootfs / 'opt/vim-tools/bin/gopls-resource-v1')
    shutil.copy2(repo / 'tests/gopls-resources.cjs', rootfs / 'usr/bin/gopls-resources.cjs')
    (rootfs / 'sys/fs/cgroup').mkdir(parents=True, exist_ok=True)
if include_additional:
    for name in ['php-resources-client.cjs', 'node-resources-client.cjs']:
        shutil.copy2(repo / 'tests' / name, rootfs / 'usr/bin' / name)
    baseline_launcher = fixture / 'resource-baseline/language-server-env-only'
    if not resource_current_only and not baseline_launcher.is_file():
        raise SystemExit('Additional LSP comparison requires .state/qemu-helper/resource-baseline/language-server-env-only')
    if not resource_current_only:
        shutil.copy2(baseline_launcher, rootfs / 'opt/vim-config/bin/language-server-env-only')
(rootfs / 'etc/passwd').write_text('root:x:0:0:root:/root:/bin/sh\ntester:x:1000:1000:tester:/home/tester:/bin/sh\n')
(rootfs / 'etc/group').write_text('root:x:0:\ntester:x:1000:\n')
(rootfs / 'home/tester/project/allowed.txt').write_text('ORIGINAL_TREE\n')
(rootfs / 'home/tester/real/okay.txt').write_text('HIDDEN_UNDER_NESTED_MOUNT\n')
(rootfs / 'home/tester/project/okay-link').symlink_to('../real')
(rootfs / 'home/tester/project/blogs.dir').symlink_to('/nfs')
(rootfs / 'init').write_text('''#!/bin/sh
export PATH=/usr/bin:/bin
/bin/busybox --install -s /bin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
chmod 1777 /tmp
mount -t tmpfs -o mode=755 allowed-nested-fixture /home/tester/real
printf 'SYMLINK_ALLOWED\\n' > /home/tester/real/okay.txt
mount -t tmpfs -o mode=755 nfs-fixture /nfs
printf 'NFS_FIXTURE_SECRET\\n' > /nfs/secret
mkdir /nfs/nested
printf 'EXTRA_SECRET\\n' > '/extra deny/secret'
printf 'GUEST_KERNEL=%s\\n' "$(uname -r)"
/bin/busybox su -s /bin/sh tester -c /usr/bin/isolation-tests
if test -x /opt/vim-tools/bin/phpantom_lsp; then
    /bin/busybox su -s /bin/sh tester -c /usr/bin/payload-tests
fi
if test -x /usr/bin/strace; then
    /usr/bin/strace -f -qq -e trace=%file -o /tmp/helper-file-trace \\
        /bin/busybox su -s /bin/sh tester -c '/opt/vim-config/bin/helper-run --profile sandbox -- /bin/true'
    trace_status=$?
    if test "$trace_status" = 0 && ! grep -E '\"/nfs(/|\")' /tmp/helper-file-trace; then
        printf 'VIM_HELPER_ZERO_TOUCH_AUDIT_PASS\\n'
    else
        printf 'FAIL_HELPER_NFS_FILE_TRACE\\n'
    fi
fi
if test -f /usr/bin/gopls-no-proc.cjs && test RUN_ORIGINAL_NO_PROC_FLAG = 1; then
    /usr/bin/unshare --mount --fork --propagation private -- /bin/sh -c \\
        'umount /proc && /bin/busybox su -s /bin/sh tester -c /usr/bin/gopls-no-proc-tests'
fi
if test -x /opt/vim-tools/bin/affinity-exec; then
    /bin/busybox su -s /bin/sh tester -c /usr/bin/affinity-tests
fi
if test -f /usr/bin/gopls-resources.cjs; then
    mount -t cgroup2 cgroup2 /sys/fs/cgroup
    VIM_QEMU_RESOURCE_CURRENT_ONLY=RESOURCE_CURRENT_ONLY_FLAG VIM_QEMU_RESOURCE_FAMILIES=RESOURCE_FAMILIES_FLAG VIM_QEMU_ADDITIONAL_LSPS=ADDITIONAL_LSPS_FLAG UV_THREADPOOL_SIZE=1 /opt/vim-tools/bin/node --v8-pool-size=1 /usr/bin/gopls-resources.cjs
fi
poweroff -f
'''.replace('ADDITIONAL_LSPS_FLAG', '1' if include_additional else '0').replace('RESOURCE_FAMILIES_FLAG', resource_families).replace('RESOURCE_CURRENT_ONLY_FLAG', '1' if resource_current_only else '0').replace('RUN_ORIGINAL_NO_PROC_FLAG', '1' if run_original_no_proc else '0'))
(rootfs / 'usr/bin/isolation-tests').write_text('''#!/bin/sh
set -eu
export PATH=/usr/bin:/bin
printf 'GUEST_UID=%s\\n' "$(id -u)"
test "$(id -u)" = 1000
printf 'GUEST_UNSHARE=%s\\n' "$(command -v unshare)"
/usr/bin/unshare --version
cd /home/tester/project
runner=/opt/vim-config/bin/helper-run
test "$(cat blogs.dir/secret)" = NFS_FIXTURE_SECRET
export VIM_CONFIG_DENY_PATHS='/nfs/nested
/extra deny'
"$runner" --profile sandbox -- /bin/sh -c '
    set -eu
    test "$PWD" = /home/tester/project
    test "$(cat allowed.txt)" = ORIGINAL_TREE
    test "$(cat okay-link/okay.txt)" = SYMLINK_ALLOWED
    test -z "$(ls -A /nfs)"
    test -z "$(ls -A blogs.dir)"
    ! cat blogs.dir/secret 2>/dev/null
    ! cat /nfs/secret 2>/dev/null
    ! cat "/extra deny/secret" 2>/dev/null
    ! cat /proc/1/root/nfs/secret 2>/dev/null
    ! touch /nfs/new-file 2>/dev/null
    ! umount /nfs 2>/dev/null
    test "$(sed -n "s/^CapBnd:[[:space:]]*//p" /proc/self/status)" = 0000000000000000
    printf "SANDBOX_MASK_PROC_CAPS_CWD_OK\\n"
'
test "$(printf 'PIPE_INPUT_OK\\n' | "$runner" --profile sandbox -- /bin/sh -c 'IFS= read -r line; printf "%s" "$line"')" = PIPE_INPUT_OK
printf 'SANDBOX_STDIN_PIPE_OK\\n'
"$runner" --profile sandbox -- /bin/sh -c 'printf ready > /tmp/helper-ready; while :; do sleep 10; done' &
supervisor=$!
attempt=0
while test ! -f /tmp/helper-ready && test "$attempt" -lt 50; do
    sleep 0.1
    attempt=$((attempt + 1))
done
test -f /tmp/helper-ready
kill -TERM "$supervisor"
if wait "$supervisor"; then
    printf 'FAIL_SUPERVISOR_TERM_STATUS\\n'; exit 1
fi
test -z "$(find /tmp -maxdepth 1 -name 'vim-config-root.*' -print)"
printf 'SANDBOX_TERM_CLEANUP_OK\\n'
test "$(cat blogs.dir/secret)" = NFS_FIXTURE_SECRET
VIM_CONFIG_DENY_PATHS=/home/tester/does-not-exist
export VIM_CONFIG_DENY_PATHS
if "$runner" --profile sandbox -- /bin/sh -c 'touch /home/tester/UNSAFE_HELPER_STARTED'; then
    printf 'FAIL_MISSING_MASK_DID_NOT_BLOCK\\n'; exit 1
fi
test ! -e /home/tester/UNSAFE_HELPER_STARTED
printf 'SANDBOX_FAIL_CLOSED_OK\\n'
printf 'VIM_HELPER_LINUX_INTEGRATION_PASS\\n'
''')
(rootfs / 'usr/bin/payload-tests').write_text('''#!/bin/sh
set -eu
export PATH=/usr/bin:/bin
export GOTELEMETRY=off
runner=/opt/vim-config/bin/helper-run
"$runner" --profile sandbox -- /opt/vim-tools/bin/phpantom_lsp --version
"$runner" --profile sandbox -- /opt/vim-tools/bin/node --eval 'if (process.platform !== "linux" || process.arch !== "x64") process.exit(1); console.log("NODE_LINUX_RUNTIME_OK " + process.version)'
"$runner" --profile sandbox -- /opt/vim-tools/bin/gopls version
printf 'VIM_HELPER_LINUX_PAYLOADS_PASS\\n'
''')
(rootfs / 'usr/bin/gopls-no-proc-tests').write_text('''#!/bin/sh
set -eu
export PATH=/usr/bin:/bin
test ! -e /proc/self/exe
exec /opt/vim-tools/bin/node /usr/bin/gopls-no-proc.cjs
''')
(rootfs / 'usr/bin/affinity-child-test').write_text('''#!/bin/sh
set -eu
cpus=$(sed -n 's/^Cpus_allowed_list:[[:space:]]*//p' /proc/self/status)
case "$cpus" in *[!0-9]*) exit 1 ;; esac
test -n "$cpus"
printf 'AFFINITY_ONE_CPU_PASS %s\\n' "$cpus"
''')
(rootfs / 'usr/bin/affinity-tests').write_text('''#!/bin/sh
set -eu
helper=/opt/vim-tools/bin/affinity-exec
"$helper" /bin/sh /usr/bin/affinity-child-test
if grep -q '^Cpus_allowed_list:[[:space:]]*0-7$' /proc/self/status; then
    test "$(/bin/busybox taskset -c 3 "$helper" /bin/sh /usr/bin/affinity-child-test)" = 'AFFINITY_ONE_CPU_PASS 3'
    printf 'AFFINITY_INHERITED_NONZERO_CPU_PASS\\n'
fi
if test -x /usr/bin/strace; then
    for call in sched_getaffinity sched_setaffinity; do
        marker=/home/tester/affinity-unsafe-child-$call
        if /usr/bin/strace -f -qq -o /tmp/affinity-inject-$call -e inject=$call:error=EPERM \\
            "$helper" /bin/sh -c 'touch "$1"' affinity-test "$marker"; then
            printf 'FAIL_AFFINITY_DENIAL_STARTED_CHILD\\n'; exit 1
        fi
        test ! -e "$marker"
        printf 'AFFINITY_DENIAL_FAIL_CLOSED_PASS %s\\n' "$call"
    done
fi
printf 'VIM_AFFINITY_REGRESSION_PASS\\n'
''')
for relative in ['init', 'usr/bin/isolation-tests', 'usr/bin/payload-tests', 'usr/bin/gopls-no-proc-tests', 'usr/bin/affinity-tests', 'usr/bin/affinity-child-test']:
    (rootfs / relative).chmod(0o755)

# Write newc without requiring host root or creating host device nodes.
archive = bytearray()
inode = 1
def entry(name, mode, data=b'', uid=0, gid=0, major=0, minor=0):
    global inode
    encoded = name.encode() + b'\0'
    fields = [inode, mode, uid, gid, 1, 0, len(data), 0, 0, major, minor, len(encoded), 0]
    archive.extend(b'070701' + b''.join(f'{value:08x}'.encode() for value in fields))
    archive.extend(encoded)
    archive.extend(b'\0' * (-len(archive) % 4))
    archive.extend(data)
    archive.extend(b'\0' * (-len(archive) % 4))
    inode += 1
for path in sorted(rootfs.rglob('*')):
    relative = path.relative_to(rootfs).as_posix()
    info = path.lstat()
    data = os.readlink(path).encode() if path.is_symlink() else path.read_bytes() if path.is_file() else b''
    owner = 1000 if relative == 'home/tester' or relative.startswith('home/tester/') or relative == 'opt/vim-config/.state' else 0
    entry(relative, info.st_mode, data, owner, owner)
for name, major, minor in [('dev/console', 5, 1), ('dev/null', 1, 3), ('dev/tty', 5, 0)]:
    entry(name, stat.S_IFCHR | 0o666, major=major, minor=minor)
entry('TRAILER!!!', 0)
initrd = fixture / 'test-initramfs.cpio.gz'
initrd.write_bytes(gzip.compress(archive, compresslevel=1 if include_no_proc else 9, mtime=0))
command = [qemu, '-machine', 'q35,accel=tcg', '-cpu', 'qemu64,+rdrand,+rdseed',
           '-m', '4096M' if include_resources else '3072M' if include_no_proc else '1024M' if include_payloads else '512M',
           '-smp', '8' if include_resources else '2' if include_no_proc else '1', '-kernel', str(kernel), '-initrd', str(initrd),
           '-append', 'console=ttyS0 rdinit=/init loglevel=3 panic=1 random.trust_cpu=on',
           '-display', 'none', '-serial', 'stdio', '-monitor', 'none', '-no-reboot', '-nic', 'none']
console = fixture / 'test-console.log'
with console.open('wb') as log:
    guest = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
    try:
        guest.wait(timeout=900 if include_resources else 240 if include_no_proc else 90)
    except subprocess.TimeoutExpired:
        guest.kill()
        guest.wait()
        raise SystemExit('QEMU timeout; inspect .state/qemu-helper/test-console.log')
output = console.read_bytes()
print(output.decode(errors='replace'))
if b'VIM_HELPER_LINUX_INTEGRATION_PASS' not in output:
    raise SystemExit('Linux helper isolation test failed')
if (rootfs / 'usr/bin/strace').exists() and b'VIM_HELPER_ZERO_TOUCH_AUDIT_PASS' not in output:
    raise SystemExit('Original /nfs path syscall audit failed')
if include_payloads and b'VIM_HELPER_LINUX_PAYLOADS_PASS' not in output:
    raise SystemExit('Linux payload startup check failed')
if run_original_no_proc and b'VIM_GOPLS_NO_PROC_REGRESSION_PASS' not in output:
    raise SystemExit('Go no-/proc regression failed')
if include_resources and b'VIM_GOPLS_RESOURCE_REGRESSION_PASS' not in output:
    raise SystemExit('Go process/thread resource regression failed')
if (rootfs / 'opt/vim-tools/bin/affinity-exec').exists() and b'VIM_AFFINITY_REGRESSION_PASS' not in output:
    raise SystemExit('Affinity selection/fail-closed regression failed')
print('PASS: real Linux namespace/mask/proc/capability tests; fixture mount is tmpfs, not an NFS server')
PY
