#!/usr/bin/env python3
"""Run a real Vim terminal acceptance script without dumping terminal escapes."""
import fcntl
import os
from pathlib import Path
import pty
import select
import struct
import subprocess
import sys
import termios
import time

root = Path(__file__).resolve().parents[1]
script = sys.argv[1] if len(sys.argv) > 1 else 'tests/test-ui.vim'
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 120, 0, 0))
env = {**os.environ, 'TERM': 'xterm-256color', 'VIM_CONFIG_PROFILE': 'misc', 'VIM_CONFIG_TEST_POPUPS': '1'}
command = [env.get('VIM_TEST_BIN', 'vim'), '-Nu', str(root / 'vimrc'), '-i', 'NONE', '-n', '-S', script]
process = subprocess.Popen(command, cwd=root, env=env, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
os.close(slave)
log = bytearray()
deadline = time.monotonic() + 90
try:
    while process.poll() is None:
        if time.monotonic() > deadline:
            process.kill()
            raise TimeoutError('terminal test exceeded 90 seconds')
        if select.select([master], [], [], .1)[0]:
            try:
                chunk = os.read(master, 65536)
            except OSError:
                break
            if not chunk:
                break
            log.extend(chunk)
    status = process.wait(timeout=5)
finally:
    os.close(master)
    if process.poll() is None:
        process.kill()
        process.wait()
out = root / '.state/tests'
out.mkdir(parents=True, exist_ok=True)
(out / (Path(script).stem + '-terminal.log')).write_bytes(log)
print(('PASS' if status == 0 else 'FAIL') + ': terminal ' + script)
sys.exit(status)
