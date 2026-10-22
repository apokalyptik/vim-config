# PHPantom Linux restricted-container patch

The Linux payload is **0.11.1+vim-config.1**, rebuilt from PHPantom 0.11.1,
commit `1756b1f920c1290d4c4fdd4d2c902fad53a75cd3`. The macOS payload remains
the upstream release. PHPantom's MIT licence and all pinned Cargo dependency
licences remain in this checkout.

Only `src/main.rs` is changed. With `VIM_CONFIG_LOW_RESOURCE=1`, its existing
Tokio runtime builder uses one async worker and at most four blocking workers.
Other values retain upstream's builder defaults. Blocking workers handle
stdio and synchronous request work; they are separate from async workers and
were not constrained by CPU affinity. The launcher separately narrows Linux
CPU affinity, which also reduces PHPantom's manually sized indexing pools.
These settings reduce concurrency; they do not impose a kernel task ceiling.

The server still embeds the complete PHPStorm stubs pinned by upstream's
`stubs.lock`, commit `5f68c1021badebe34119fb8fa10ba7cc25de6c0c`. The build
verifies their archive checksum and checks the build output confirms their
embedded revision. The `offline-stubs` feature prevents a build-time network
fallback; it does not remove the prepared stubs.

The source archive, patch input/output, patch helper, Cargo lock, Rust compiler
and standard libraries, Zig archive, and output payload are pinned in
`tools/vendor-manifest.json`. The binary is a stripped static musl executable.
Rust library copyright and licence texts, musl copyright, and LLVM libunwind
terms are preserved in `vendor/licenses/phpantom-runtime/`; the included Rust
licence-text collection is a superset of the linked runtime's terms.

The preparation recipe currently uses a macOS arm64 host, Cargo 1.99.1, the
pinned official Rust 1.99.1 compiler/standard libraries, and Zig 0.15.2. It
does not alter the host Rust installation or its Cargo caches. It obtains
Cargo sources only from archives checked against the upstream lockfile, then
compiles with Cargo's `--locked --offline` flags. All caches are task-local.

```sh
python3 tools/prepare-bundle.py --rebuild-phpantom --work-dir /absolute/preparation-directory
```

After the pinned inputs are cached, add `--offline` to prohibit preparation
downloads too. Target machines only unpack the completed payload. The
`phpantom-low-resource` marker lets container launchers reject older tools
before starting a server without these pool limits.
