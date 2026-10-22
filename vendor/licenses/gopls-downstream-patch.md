# gopls restricted-container patches

The distributed server is **v0.24.0+vim-config.2**, based on upstream
`golang.org/x/tools/gopls v0.24.0`, commit
`1f9922d1dcc5836d5c5bcb552c8fed230f885372`.

The upstream BSD-style copyright and licence remain in
`vendor/licenses/gopls-dependencies/golang.org/x/tools/gopls@v0.24.0/LICENSE`.

In `internal/filecache/filecache.go`, when Go's `os.Executable()`
cannot discover the executable (for example, `/proc/self/exe` is absent), the
server accepts `VIM_CONFIG_GOPLS_EXECUTABLE` from its launcher. The value must be
an absolute path naming the regular executable file that the launcher ran.
Missing, relative, nonregular, or unreadable files fail clearly. The fallback
never derives identity from `argv[0]` or a version string.

The existing SHA256 content-hash algorithm then reads the executable's actual
bytes. The existing cache directory naming and full-hash collision checks are
unchanged. Normal executable discovery remains the first choice, so hosts with
working `/proc` or native macOS discovery use upstream behavior.

An additional dependency patch changes the concurrency declarations and
`Invocation.run` entry in `golang.org/x/tools/internal/gocommand/invoke.go`, from pinned dependency
`v0.51.1-0.20261014163302-24a65270771e`. With the launcher's
`VIM_CONFIG_LOW_RESOURCE=1`, a process-wide semaphore permits one Go command
invocation at a time across runners, with context cancellation while waiting.
Each runner also has capacity one. Other values preserve upstream's limit of
ten per runner without the global gate. Both normal commands and the existing
exclusive-command path use the same limits.
The dependency's BSD-style licence is retained alongside the gopls licence.

This reduces subprocess concurrency. It is not a hard limit on processes or
OS threads: each Go process can create additional threads, and other helpers
have their own process trees. The launcher also supplies Go's supported CPU
and package-build concurrency settings for the restricted-container profile.

As with upstream's pathname-based hashing, tools must not be replaced while a
server is running. Close Vim and its servers before updating the tool payloads.

`tools/patch-gopls.py` documents and applies the exact transformation to copies
of verified upstream module source and its x/tools dependency. Only the
temporary gopls module copy receives a replace directive selecting the patched
dependency copy. Their input and output file checksums, patch script checksum,
upstream module checksums, compiler settings, and archive
checksums are recorded in `tools/vendor-manifest.json`. The module cache itself
is not modified. The version suffix is set using upstream's supported
`-X main.version` linker variable; it is descriptive and is not a cache key.

Maintainers can rebuild just these two payloads using a prepared module cache:

```sh
python3 tools/prepare-bundle.py --rebuild-gopls --offline --work-dir /absolute/preparation-directory
```

The checked-in Go SDK is used with `CGO_ENABLED=0`, `-trimpath`, and
`-buildvcs=false`. Destination machines only unpack the completed archives.
