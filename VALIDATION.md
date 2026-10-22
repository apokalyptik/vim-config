# Trial validation

This records local evidence, not certification of the user's remote hosts or their codebases.

## Tested locally

* macOS ARM64, system Vim 9.1.1752.
* Vim **9.0.2142**, compiled locally solely to test the oldest supplied Vim version. Target installation does not compile Vim.
* Offline setup verifies pinned archives and unpacks the macOS tool bundle.
* PHPantom, Node, Go SDK and gopls executables start. The target-side doctor requires Vim and shell tools, not Python.
* Real LSP requests pass for PHP, Go, JavaScript, HTML, CSS and JSON. Go resolves `fmt.Println` into the bundled standard library with module/toolchain fetching disabled.
* Actual Vim client integration passes on both Vim versions: PHP method completion, cross-file definitions and incoming-call hierarchy.
* UI tests exercise searchable actions, arrows, Escape, F1 from insert mode, Save and resume typing, jump history, per-buffer fast mode, and CSV/servers.dat statusline parity. PTY tests exercise actual completion menus, passive Enter/arrow behavior and explicit F2 acceptance.
* VCS/data tests cover argv handling of filenames containing shell metacharacters, excluded paths, commit drafts, SVN peg syntax, temp cleanup and actual Node-backed RBQL queries. They do not submit a real commit to a user's repository.

## PHP scale and measured latency

Two synthetic PHP fixtures were used. These exercise the integration at the requested scale but cannot reproduce every large WordPress function, type graph, plugin or hook pattern.

| Test | Fixture | Observed local result |
| --- | --- | --- |
| Actual Vim client, 9.0.2142 | 513,255 bytes / 15,015 lines, plus a separate PSR-4 class | completion about 15 ms; definition about 23 ms; callers about 11 ms |
| Actual Vim client, 9.1.1752 | Same | completion about 14 ms; definition about 21 ms; callers about 11 ms |
| Direct server protocol | 602,087 bytes / 15,003 lines | initial definition about 24 ms; completion about 25 ms; incoming-call query about 4 ms |
| Vim local PTY rendering/edit dispatch | 602,006 bytes / 15,001 lines, syntax + LSP enabled, fast mode off | first open/redraw about 24 ms; cursor/redraw mean about 37 ms; insert/redraw median about 17 ms, p95 about 18 ms |

These are single-run observations on this Mac, not general benchmarks. Editor timings exclude SSH latency and physical key input; server request timings do not establish complete end-to-end key-to-screen latency. No RAM or CPU ceiling has been certified.

One PHPantom behavior remains visible in the direct protocol test: a definition request immediately after an incremental edit returned no result; retrying after 100 ms succeeded. Completion/navigation after ordinary indexing and through the Vim client passed. The test records the retry rather than hiding it as uninterrupted availability.

Fast mode stayed off for both target-sized fixtures. The 8 MiB / 100,000-line thresholds do not protect against a server independently scanning oversized workspace files; index scope must be bounded separately.

## Linux exclusion verification

The launcher was tested as **UID 1000**, on Debian kernel **6.1.0-53-amd64**, in a disposable QEMU guest with util-linux 2.38.1 and dash. It creates a new user/mount/PID namespace and a private filesystem root which omits the original top-level `/nfs` before classifying that entry. A fresh `/proc` is mounted; capabilities are dropped before the helper starts.

Verified assertions:

* Original working-directory contents and an ordinary allowed symlink remain available.
* An allowed nested project mount remains available.
* `/nfs` and `blogs.dir → /nfs` expose an empty read-only local placeholder.
* `/proc/1/root` cannot expose the original denied tree; writes and unmounting the placeholder fail; capability bounding set is zero.
* The outer filesystem remains unchanged.
* Missing required isolation or an unavailable additional deny prevents the requested helper from starting.
* A `strace -f -e trace=%file` audit of the complete launcher and its descendants found **no file syscall addressing original `/nfs`**, including during bootstrap. This tests the default top-level exclusion without an actual NFS server.
* Packaged Linux PHPantom and gopls start through the launcher; packaged Node executes JavaScript with the guest's global C++ runtime libraries deliberately absent. The guest uses glibc 2.36 and Node's private included runtime libraries.

Important boundaries:

* The guest uses a mounted fixture at `/nfs`, not the user's live NFS export. No live-NFS RPC trace was performed.
* Additional **nested** deny roots are masked within the private view; preparing those masks resolves the nested root itself. The zero-original-root-touch audit applies to the default top-level `/nfs` omission.
* The temporary-root parent is bound nonrecursively to avoid retaining the construction root. An unusual inherited submount beneath that parent can make Linux reject the operation; the helper fails closed.
* Other independent bind mounts to the same underlying remote storage are not automatically inferred from `/nfs`. Add explicit deny paths for any such aliases.
* This wrapper constrains configuration-supplied helper processes. It does not restrict Vim commands the user explicitly runs independently, manually opened files, or arbitrary extra plugins loaded by the user.

## Still required on the user's hosts

Run `bin/setup` and `bin/vim-config-doctor --profile PROFILE --lsp` on each relevant host. In particular:

* Restricted Containers: establish whether the bundled native runtimes and Go tooling can execute under the actual seccomp policy. A successful local or VM test is not a substitute.
* Work Sandbox: validate the complete isolation wrapper, permitted mount topology, tools and the actual project workflow. The earlier `namespace-ok` probe alone is insufficient.
* Try completion/navigation on a real 500 KB WordPress file and inspect CPU/memory and interactive latency there.
* Confirm iTerm function-key delivery over the user's SSH path; `:VimMenu` is available if F1 is intercepted.

Reproducible local checks: `tests/run.sh`, `python3 tests/terminal.py`, `python3 tests/terminal.py tests/benchmark-vim.vim`. `tests/qemu-helper.sh` accepts explicitly prepared kernel/BusyBox/Debian package inputs; its fixture inputs and hashes are kept in the ignored local test workspace rather than shipping a VM in the editor bundle.
