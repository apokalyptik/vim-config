# Trial validation

This records local tests and explicitly identified user-reported host results.

## Tested locally

* macOS ARM64, system Vim 9.1.1752.
* Vim **9.0.2142**, compiled locally solely to test the oldest supplied Vim version. Target installation does not compile Vim.
* Offline setup verifies pinned archives and unpacks the macOS tool bundle.
* Bash 3.2 runs setup with a PATH containing no Perl or Python. Small offline fixtures cover both SHA-256 backends, a corrupt archive, replacement rollback, a checkout path with spaces, and optional home-config backup. The same Bash installer unpacks the real macOS payloads.
* PHPantom, Node, Go SDK and gopls executables start. The target-side doctor requires Vim and shell tools, not Python.
* Real LSP requests pass for PHP, Go, JavaScript, HTML, CSS and JSON. Go resolves `fmt.Println` into the bundled standard library with module/toolchain fetching disabled.
* Actual Vim client integration passes on both Vim versions: PHP method completion, cross-file definitions and incoming-call hierarchy.
* UI tests exercise searchable actions, arrows, Escape, F1 from insert mode, Save and resume typing, jump history, per-buffer fast mode, and CSV/servers.dat statusline parity. PTY tests exercise actual completion menus, passive Enter/arrow behavior and explicit F2 acceptance.
* VCS/data tests cover argv handling of filenames containing shell metacharacters, excluded paths, commit drafts, SVN peg syntax, temp cleanup and actual Node-backed RBQL queries. They do not submit a real commit to a user's repository.
* With macOS `sandbox-exec` denying network operations, TCP and Unix bind/listen control probes fail, while gopls initializes over stdio and resolves `fmt.Println`. This does not reproduce Linux seccomp or establish compatibility with the restricted Work Container.
* Doctor failure fixtures use real Vim channels to check process exit/final stderr, error replies, malformed protocol, termination signals, timeouts, and bounded readable crash output. Probe caches and homes are temporary; telemetry mode files disable Go telemetry for the probes. A local persistent-index permission failure was reproduced and disappears with the isolated `GOPLSCACHE` path; this does not identify the container's failure.

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

An additional regression unmounts `/proc` in a separate guest mount namespace and runs as UID 1000. The original gopls reproduces the container's exact `can't hash gopls executable: readlink /proc/self/exe: no such file or directory` fatal error. The checked-in patched archive, started through the actual `bin/language-server` launcher, initializes and resolves `fmt.Println` into the bundled SDK. The client supplies neither `GOROOT` nor the fallback path, exercising the launcher's configuration. The recorded `exe.sha256` matches the actual binary's SHA-256 (`c3434d66cd8abeaca6fc724e8021bc00d14d74565df5e953abf6d216928b0177`), including the cache-directory prefix. Missing, relative, nonexistent and unreadable fallback paths are rejected. The same run passes the existing wrapper, stdin, cleanup and zero-touch audit checks.

Important boundaries:

* The guest uses a mounted fixture at `/nfs`, not the user's live NFS export. No live-NFS RPC trace was performed.
* Additional **nested** deny roots are masked within the private view; preparing those masks resolves the nested root itself. The zero-original-root-touch audit applies to the default top-level `/nfs` omission.
* The temporary-root parent is bound nonrecursively to avoid retaining the construction root. An unusual inherited submount beneath that parent can make Linux reject the operation; the helper fails closed.
* Other independent bind mounts to the same underlying remote storage are not automatically inferred from `/nfs`. Add explicit deny paths for any such aliases.
* This wrapper constrains configuration-supplied helper processes. It does not restrict Vim commands the user explicitly runs independently, manually opened files, or arbitrary extra plugins loaded by the user.

## Container process and thread budget

The user's next real-container run exceeded its 25-task allowance at 38 and disconnected SSH. The user confirmed that threads count toward that limit. Resource settings therefore apply only to `container`; other profiles retain their normal concurrency.

Linux measurements use eight visible CPUs, UID 1000, no `/proc` in the server's namespace, cold fixture caches, and the actual launcher. A supervisor outside that namespace reads cgroup `pids.peak`, which counts threads and descendant processes, including brief startup/exec transitions. The Node protocol client and observer each use four threads and are excluded from the server subtree figures below; they replace neither a full SSH session nor every possible user workload.

| Workload | Observed kernel peak in server subtree |
| --- | --- |
| Previous gopls `.1`, three module folders and standard-library definitions | 58 tasks |
| Previous gopls with only `GOMAXPROCS=1` and `-p=1` | 25 tasks |
| Current gopls `.2`, global Go-command gate, affinity and container defaults | 14 tasks / 3 programs / one direct Go command |
| Upstream PHPantom with affinity, 102 PHP files and default workspace diagnostics enabled | 24 tasks, exceeding the safe budget |
| Patched PHPantom, production and default-diagnostics stress cases, 102 files including a 485,286-byte / 15,001-line file | 7–8 tasks |
| TypeScript cross-file definition and property completion | 10 tasks across the parent and one semantic child |

All three current workloads also complete under an enforced 18-task subtree limit with zero refused task creations. Both PHP initialization variants complete definitions, completion and natural EOF exit with an empty helper cgroup. The patched Linux PHP binary limits Tokio to one async worker and four blocking workers in container mode; the tested binary's SHA-256 is `528c27d32c84d6af57f15ceb3b0a3178623164a96b2ea92019a1953a65f0a583`, independently checked against the final archive. Across the affinity Go runs, observed peaks varied up to 15 tasks. CPU-affinity checks preserve an inherited CPU-3-only mask and reject injected GET/SET-affinity errors before a marker child runs. The Go, affinity and patched PHP binaries rebuild byte-for-byte from prepared offline inputs. These observations establish headroom for these fixtures, not a hard bound for arbitrary projects, custom commands, multiple Vim instances or other SSH jobs. `GOMEMLIMIT` is a soft target; no total RAM ceiling is certified.

Native Vim lifecycle tests exercise JS/TS process reuse, switching families, restoring unsaved buffers, hidden same-family buffers, and refusing to start another family while a deliberately slow server is still exiting. PHP can stall after protocol shutdown; the bundled PHP launcher alone receives a bounded TERM fallback after the two-second wait. The next family starts only after confirmed exit. Other lingering servers require a later buffer re-entry to retry. The TypeScript archive includes its missing shutdown callback, and a container-only preload waits for child handles to close before parent exit. A delayed-child fixture checks this ordering. Container Go uses private telemetry-off configuration and disables optional background vulnerability scanning and custom package drivers.

## User-reported Work Container verification

On 2026-10-22, the user reported a complete `bin/vim-config-doctor --profile container --lsp` pass after setup on Vim 9.1.1244, glibc 2.41 and kernel 6.12.107+deb13-amd64. The report confirms:

* PHPantom `0.11.1+vim-config.1`, Node `24.22.1`, Go SDK `1.27.3` and gopls `0.24.0+vim-config.2` start on the actual restricted host.
* PHP LSP initialization and fixture definition lookup pass.
* Go LSP initialization and standard-library definition lookup pass with functioning bundled Go tooling.

This replaces the earlier failed doctor results caused by missing `/proc/self/exe` and excessive process/thread use. The successful doctor uses temporary fixture projects; actual project completion, navigation and sustained resource use remain the next trial.

## Still required on the user's hosts

Run `bin/setup` and `bin/vim-config-doctor --profile PROFILE --lsp` on each relevant host. In particular:

* Restricted Containers: try the full Vim workflow on real projects, including JavaScript/HTML/CSS/JSON server use and language-family switching. The host doctor pass covers runtime startup and PHP/Go fixture navigation.
* Work Sandbox: validate the complete isolation wrapper, permitted mount topology, tools and the actual project workflow. The earlier `namespace-ok` probe alone is insufficient.
* Try completion/navigation on a real 500 KB WordPress file and inspect CPU/memory and interactive latency there.
* Confirm iTerm function-key delivery over the user's SSH path; `:VimMenu` is available if F1 is intercepted.

Reproducible local checks: `tests/run.sh`, `python3 tests/terminal.py`, `python3 tests/terminal.py tests/benchmark-vim.vim`. `tests/qemu-helper.sh` accepts explicitly prepared kernel/BusyBox/Debian package inputs; its fixture inputs and hashes are kept in the ignored local test workspace rather than shipping a VM in the editor bundle.

For the Linux procfs regression, add `VIM_CONFIG_QEMU_GOPLS_NO_PROC=1` and set `VIM_CONFIG_QEMU_GOPLS_BASELINE` to the original unpatched Linux gopls executable (available from the payload at commit `ec2abe6`). The fixture uses the checked-in patched archive unless an explicit test-only binary override is supplied; the verified run used the archive without an override.

For resource checks, set `VIM_CONFIG_QEMU_GOPLS_RESOURCES=1` and `VIM_CONFIG_QEMU_ADDITIONAL_LSPS=1`. `VIM_CONFIG_QEMU_RESOURCE_CURRENT_ONLY=1` skips historical comparisons, and `VIM_CONFIG_QEMU_RESOURCE_FAMILIES=php,typescript` selects focused cases. The PHP fixture includes both production initialization and the default-diagnostics stress case. The supervisor measures kernel task peaks and repeats each current workload with `pids.max=18`; it also requires zero denial events and an empty helper cgroup afterward.
