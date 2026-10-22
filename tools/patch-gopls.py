#!/usr/bin/env python3
"""Apply the pinned gopls filecache fallback to a writable source COPY.

Upstream: golang.org/x/tools/gopls v0.24.0, commit
1f9922d1dcc5836d5c5bcb552c8fed230f885372. Its BSD licence is retained.
The launcher explicitly supplies the executable pathname; argv[0] is never used.
Cache invalidation still uses SHA256 of the executable's actual contents.
"""
import argparse
import hashlib
from pathlib import Path

SOURCE_SHA256 = '7ad9c9d8ca9ad0e7486bfdbf43068e73c7e34597ee5248f4f289e1aa7cfb2dea'
ORIGINAL = '''func hashExecutable() (hash [32]byte, err error) {
	exe, err := os.Executable()
	if err != nil {
		return hash, err
	}
	f, err := os.Open(exe)
	if err != nil {
		return hash, err
	}
	defer f.Close()
'''
PATCHED = '''func hashExecutable() (hash [32]byte, err error) {
	exe, err := os.Executable()
	fallback := err != nil
	if fallback {
		// Downstream: /proc/self/exe is absent in some restricted containers.
		// The launcher supplies the exact binary path it executed. Never infer
		// identity from argv[0] or a version string: hash the actual file below.
		exe = os.Getenv("VIM_CONFIG_GOPLS_EXECUTABLE")
		if !filepath.IsAbs(exe) {
			return hash, fmt.Errorf("cannot locate executable (%w): VIM_CONFIG_GOPLS_EXECUTABLE must name the absolute running gopls binary path", err)
		}
	}
	f, err := os.Open(exe)
	if err != nil {
		return hash, err
	}
	defer f.Close()
	if fallback {
		info, err := f.Stat()
		if err != nil {
			return hash, err
		}
		if !info.Mode().IsRegular() {
			return hash, fmt.Errorf("VIM_CONFIG_GOPLS_EXECUTABLE is not a regular file: %s", exe)
		}
	}
'''


def patched_source(source):
    if hashlib.sha256(source).hexdigest() != SOURCE_SHA256:
        raise RuntimeError('Unexpected gopls filecache source: expected the exact pinned v0.24.0 file')
    text = source.decode('utf-8')
    if text.count(ORIGINAL) != 1:
        raise RuntimeError('Expected exactly one upstream hashExecutable block')
    return text.replace(ORIGINAL, PATCHED).encode('utf-8')


def apply(directory):
    target = directory / 'internal/filecache/filecache.go'
    before = target.read_bytes()
    if PATCHED in before.decode('utf-8'):
        original = before.decode('utf-8').replace(PATCHED, ORIGINAL).encode('utf-8')
        if hashlib.sha256(original).hexdigest() != SOURCE_SHA256:
            raise RuntimeError('Patched source contains unexpected additional changes')
        return before
    after = patched_source(before)
    target.chmod(target.stat().st_mode | 0o200)
    target.write_bytes(after)
    return after


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source_copy', type=Path, help='writable copy of the pinned gopls module')
    args = parser.parse_args()
    result = apply(args.source_copy)
    print('Patched gopls filecache SHA256: ' + hashlib.sha256(result).hexdigest())


if __name__ == '__main__':
    main()
