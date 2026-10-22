# gopls restricted-container executable discovery patch

The distributed server is **v0.24.0+vim-config.1**, based on upstream
`golang.org/x/tools/gopls v0.24.0`, commit
`1f9922d1dcc5836d5c5bcb552c8fed230f885372`.

The upstream BSD-style copyright and licence remain in
`vendor/licenses/gopls-dependencies/golang.org/x/tools/gopls@v0.24.0/LICENSE`.

Only `internal/filecache/filecache.go` is changed. When Go's `os.Executable()`
cannot discover the executable (for example, `/proc/self/exe` is absent), the
server accepts `VIM_CONFIG_GOPLS_EXECUTABLE` from its launcher. The value must be
an absolute path naming the regular executable file that the launcher ran.
Missing, relative, nonregular, or unreadable files fail clearly. The fallback
never derives identity from `argv[0]` or a version string.

The existing SHA256 content-hash algorithm then reads the executable's actual
bytes. The existing cache directory naming and full-hash collision checks are
unchanged. Normal executable discovery remains the first choice, so hosts with
working `/proc` or native macOS discovery use upstream behavior.

As with upstream's pathname-based hashing, tools must not be replaced while a
server is running. Close Vim and its servers before updating the tool payloads.

`tools/patch-gopls.py` documents and applies the exact transformation to a copy
of verified upstream module source. Its input and output file checksums, patch
script checksum, upstream module checksum, compiler settings, and archive
checksums are recorded in `tools/vendor-manifest.json`. The module cache itself
is not modified. The version suffix is set using upstream's supported
`-X main.version` linker variable; it is descriptive and is not a cache key.

Maintainers can rebuild just these two payloads using a prepared module cache:

```sh
python3 tools/prepare-bundle.py --rebuild-gopls --offline --work-dir /absolute/preparation-directory
```

The checked-in Go SDK is used with `CGO_ENABLED=0`, `-trimpath`, and
`-buildvcs=false`. Destination machines only unpack the completed archives.
