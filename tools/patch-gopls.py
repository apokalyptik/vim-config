#!/usr/bin/env python3
"""Apply the pinned gopls fixes to writable source COPIES.

Upstream: golang.org/x/tools/gopls v0.24.0, commit
1f9922d1dcc5836d5c5bcb552c8fed230f885372. Its BSD licence is retained.
The launcher explicitly supplies the executable pathname; argv[0] is never used.
Cache invalidation still uses SHA256 of the executable's actual contents.
The optional x/tools dependency patch limits Go command concurrency only when the
launcher explicitly selects the restricted-container resource profile.
"""
import argparse
import hashlib
from pathlib import Path

SOURCE_SHA256 = '7ad9c9d8ca9ad0e7486bfdbf43068e73c7e34597ee5248f4f289e1aa7cfb2dea'
GOCOMMAND_SOURCE_SHA256 = '6a07f4ecd3e7566643810962ba551001b50bd4403e87a915327899f0cd6d55a5'
GOCOMMAND_ORIGINAL = 'const maxInFlight = 10\n'
GOCOMMAND_PATCHED = '''// Downstream: serialize Go subprocesses in the restricted-container profile.
// GOMAXPROCS and go -p constrain each command, not concurrent invocations.
var maxInFlight = func() int {
	if os.Getenv("VIM_CONFIG_LOW_RESOURCE") == "1" {
		return 1
	}
	return 10
}()

// Workspace discovery can create additional Runners. Share one process-wide
// gate so those runners cannot each start their own concurrent Go command.
var lowResourceGoCommandGate = make(chan struct{}, 1)
'''
GOCOMMAND_RUN_ORIGINAL = '''func (i *Invocation) run(ctx context.Context, stdout, stderr io.Writer) error {
	goArgs := []string{i.Verb}
'''
GOCOMMAND_RUN_PATCHED = '''func (i *Invocation) run(ctx context.Context, stdout, stderr io.Writer) error {
	if maxInFlight == 1 {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case lowResourceGoCommandGate <- struct{}{}:
			defer func() { <-lowResourceGoCommandGate }()
		}
	}
	goArgs := []string{i.Verb}
'''
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


def apply_gocommand(target):
    """Patch only a copy of the exact pinned x/tools dependency file."""
    before = target.read_bytes()
    text = before.decode('utf-8')
    if GOCOMMAND_PATCHED in text:
        original = text.replace(GOCOMMAND_PATCHED, GOCOMMAND_ORIGINAL).replace(GOCOMMAND_RUN_PATCHED, GOCOMMAND_RUN_ORIGINAL).encode('utf-8')
        if hashlib.sha256(original).hexdigest() != GOCOMMAND_SOURCE_SHA256:
            raise RuntimeError('Patched gocommand source contains unexpected additional changes')
        return before
    if hashlib.sha256(before).hexdigest() != GOCOMMAND_SOURCE_SHA256:
        raise RuntimeError('Unexpected x/tools gocommand source: expected the exact pinned dependency file')
    if text.count(GOCOMMAND_ORIGINAL) != 1 or text.count(GOCOMMAND_RUN_ORIGINAL) != 1:
        raise RuntimeError('Expected exactly one upstream maxInFlight declaration and Invocation.run entry')
    after = text.replace(GOCOMMAND_ORIGINAL, GOCOMMAND_PATCHED).replace(GOCOMMAND_RUN_ORIGINAL, GOCOMMAND_RUN_PATCHED).encode('utf-8')
    target.chmod(target.stat().st_mode | 0o200)
    target.write_bytes(after)
    return after


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source_copy', type=Path, help='writable copy of the pinned gopls module')
    parser.add_argument('--gocommand-file', type=Path, help='writable copy of the pinned x/tools internal/gocommand/invoke.go')
    args = parser.parse_args()
    result = apply(args.source_copy)
    print('Patched gopls filecache SHA256: ' + hashlib.sha256(result).hexdigest())
    if args.gocommand_file:
        result = apply_gocommand(args.gocommand_file)
        print('Patched x/tools gocommand SHA256: ' + hashlib.sha256(result).hexdigest())


if __name__ == '__main__':
    main()
