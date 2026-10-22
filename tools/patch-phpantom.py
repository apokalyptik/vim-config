#!/usr/bin/env python3
"""Bound PHPantom's Tokio pools only in the restricted-container profile.

Applies to the exact main.rs from PHPantom 0.11.1, commit
1756b1f920c1290d4c4fdd4d2c902fad53a75cd3. Upstream MIT licence retained.
"""
import hashlib
from pathlib import Path
import sys

UPSTREAM_SHA256 = '2061db18219a3685b128da0ae9faa1c9db1b0beec23cfeb3834b769e4312fc10'
ORIGINAL = '''    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .thread_stack_size(PARSE_WORKER_STACK_SIZE)
        .build()
        .expect("failed to build Tokio runtime");'''
PATCHED = '''    // vim-config downstream: bound the separate blocking pool in restricted
    // containers; CPU affinity alone does not constrain Tokio blocking I/O.
    let mut builder = tokio::runtime::Builder::new_multi_thread();
    builder.enable_all().thread_stack_size(PARSE_WORKER_STACK_SIZE);
    if std::env::var("VIM_CONFIG_LOW_RESOURCE").as_deref() == Ok("1") {
        builder.worker_threads(1).max_blocking_threads(4);
    }
    let runtime = builder.build().expect("failed to build Tokio runtime");'''


def patch(path):
    before = path.read_bytes()
    text = before.decode('utf-8')
    if PATCHED in text:
        if text.count(PATCHED) != 1:
            raise RuntimeError('Ambiguous patched PHPantom runtime builder')
        upstream = text.replace(PATCHED, ORIGINAL).encode('utf-8')
        if hashlib.sha256(upstream).hexdigest() != UPSTREAM_SHA256:
            raise RuntimeError('Patched PHPantom source contains unexpected additional changes')
        return before
    if hashlib.sha256(before).hexdigest() != UPSTREAM_SHA256:
        raise RuntimeError('PHPantom main.rs does not match pinned upstream source')
    if text.count(ORIGINAL) != 1:
        raise RuntimeError('Expected exactly one upstream PHPantom runtime builder')
    after = text.replace(ORIGINAL, PATCHED).encode('utf-8')
    path.write_bytes(after)
    return after


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: patch-phpantom.py /path/to/phpantom/src/main.rs')
    result = patch(Path(sys.argv[1]))
    print('Patched PHPantom main.rs SHA256: ' + hashlib.sha256(result).hexdigest())
