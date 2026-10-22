#!/usr/bin/env python3
"""Wire pinned TSLS shutdown to its normal child cleanup; build-host only."""
import hashlib
from pathlib import Path
import sys

UPSTREAM_SHA256 = '192638f1fa62c907fd54c0b55b12dd3dff01325a1a0ed5973907efca1c57b5eb'
NEEDLE = b'  connection.onInitialized(server.initialized.bind(server));\n'
INSERTION = b'  connection.onShutdown(server.shutdown.bind(server)); // vim-config downstream: dispose children on LSP shutdown.\n'


def patch(path):
    original = path.read_bytes()
    if INSERTION in original:
        if original.count(INSERTION) != 1:
            raise RuntimeError('ambiguous TS shutdown callback')
        upstream = original.replace(INSERTION, b'', 1)
        if hashlib.sha256(upstream).hexdigest() != UPSTREAM_SHA256:
            raise RuntimeError('patched TSLS source does not match pinned upstream')
        return
    if hashlib.sha256(original).hexdigest() != UPSTREAM_SHA256:
        raise RuntimeError('TSLS source checksum mismatch')
    if original.count(NEEDLE) != 1:
        raise RuntimeError('TSLS connection registration changed')
    path.write_bytes(original.replace(NEEDLE, NEEDLE + INSERTION, 1))


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: patch-typescript.py /path/to/typescript-language-server/lib/cli.mjs')
    patch(Path(sys.argv[1]))
