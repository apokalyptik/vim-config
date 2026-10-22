# TypeScript language server shutdown patch

The JavaScript payload contains typescript-language-server **6.0.2** with one
local shutdown registration in its prepared `lib/cli.mjs`. The upstream
Apache-2.0 licence is preserved in the payload and in
`vendor/licenses/javascript-dependencies/typescript-language-server/LICENSE`.
The modified line carries a downstream notice.

The patch registers `connection.onShutdown(server.shutdown.bind(server))` next
to the existing initialization callbacks. It invokes the server's existing
cleanup, which disposes tsserver listeners and terminates its child process.
The container launcher then waits for child handles to close before allowing
the language-server parent to exit. No forced kill, timeout, or extra process
is introduced by this callback.

The pinned npm package URL and integrity, input/output CLI file checksums, and
exact patch-helper checksum are recorded in `tools/vendor-manifest.json`.
`tools/patch-typescript.py` rejects unrecognized input and reapplies the patch
idempotently. The preparation script applies it after a fresh npm installation.
Maintainers can also repack only the existing verified JavaScript archive:

```sh
python3 tools/prepare-bundle.py --rebuild-javascript --offline --work-dir /absolute/preparation-directory
```

That partial operation requires neither network access nor npm nor a compiler.
Target machines only unpack the completed archive.
