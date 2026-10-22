# Portable Vim configuration

A native Vim 9 trial built around arrow-key editing, insert mode, and one searchable action menu. The checked-in tool bundle supports Linux x86-64 (including WSL) and macOS ARM64. No download, package manager, or compiler is needed during setup or ordinary startup.

## Try it

```sh
git clone --branch codex/native-vim-trial https://github.com/apokalyptik/vim-config.git ~/.vim-config
cd ~/.vim-config
./bin/setup --profile sandbox
./bin/vim-config-doctor --profile sandbox --lsp
./bin/vim-config ~/public_html/index.php
```

Choose the profile for that host:

| Profile | Environment | Helper behavior |
| --- | --- | --- |
| `container` | Restricted Work Containers | Direct execution with reduced worker pools and serialized Go commands; target-host checks still required |
| `sandbox` | Work Sandbox with `blogs.dir → /nfs` | Isolated helper filesystem; `/nfs` is hidden; failure prevents the helper from starting |
| `misc` | Work Misc Hosts | Direct execution |
| `laptop` | macOS ARM64 | Direct execution |
| `wsl` | Home Windows through Linux x86-64 WSL | Direct execution |

Setup uses Bash (including macOS's bundled Bash 3.2), tar, and either `sha256sum` or `openssl`. It verifies and unpacks only the current platform plus shared JavaScript servers into ignored `.state/tools`. About 282 MiB of compressed payloads are checked in for both platforms; unpacking a platform needs considerably more space. Setup writes inside this checkout. It does not alter your existing Vim configuration unless you explicitly add `--link-home`; that option backs up `~/.vimrc` before linking this configuration.

Use `./bin/vim-config --profile container file.php` for a one-off profile override. Keep the checkout at its installed location when using the home symlink. Close Vim before updating and re-running setup so running servers keep the matching tool files. Vim startup never runs setup or downloads tools.

## Editing

* **F1** opens actions. Type to filter; use arrows and Enter to choose; Escape dismisses. `:VimMenu` is a fallback if a terminal intercepts F1.
* Suggestions appear without selecting a match. Ordinary arrow keys dismiss suggestions and move the cursor. Enter inserts a newline; Tab indents.
* **F2** deliberately enters completion selection. Up/Down preview choices and Enter accepts. Escape dismisses the completion menu. Outside a popup, Escape retains normal Vim behavior.
* Existing `v`, `V`, Ctrl+V selections and Vim registers are retained. Mouse reporting is off so terminal selection remains available. There is no system-clipboard dependency.
* Formatting and refactoring are explicit menu actions. Diagnostics use small signs, with no automatic hover, virtual text, code lens, or inlay hints.
* F1 → Close current panel/window returns from result panes. Unsaved edits retain Vim's normal close protection.

## Language tools

PHP uses **PHPantom 0.11.1**; Go uses **gopls with a complete Go SDK**; JavaScript/TypeScript uses TypeScript's JavaScript server and typescript-language-server; HTML/CSS/JSON use vscode-langservers-extracted. All are supplied, including the Node runtime. Versions, source URLs, hashes, build provenance, and entrypoints are in [the manifest](tools/vendor-manifest.json). Licences are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and `vendor/licenses`.

PHPantom is an actively developing server, so this is a trial rather than a claim of PHPStorm-equivalent analysis. Definitions, references, and incoming/outgoing calls are exposed through F1. Dynamic PHP calls and WordPress hooks cannot be assumed to produce a complete call graph. WordPress core/plugins/themes must be inside the allowed indexed workspace for their source symbols to be found.

Go toolchains and module downloads are disabled automatically (`GOTOOLCHAIN=local`, `GOPROXY=off`, `GOSUMDB=off`). Project dependencies must already be vendored or cached; arbitrary project dependencies are not part of this editor bundle. Missing dependencies and projects requiring a different SDK may need a prepared dependency/toolchain update. Cgo packages can additionally need their C compiler, headers, and libraries. A blocked GCC does not establish whether the supplied pure-Go tooling can run under a given seccomp policy.

TypeScript automatic type acquisition and JSON remote schema downloads are disabled. Add desired type packages and schemas to the project explicitly. SQL has Vim syntax support; database-aware schema completion is a later, dialect-specific addition.

The Linux Node bundle includes private C++ runtime libraries so it does not depend on an apt-installed `libstdc++`. The system glibc/loader is still required; the packaged baseline is Debian 12 / glibc 2.36 or newer. PHPantom and gopls use static Linux builds. These packaging choices do not bypass seccomp restrictions.

The bundled gopls includes a small compatibility patch for containers without `/proc/self/exe`. When its normal executable lookup fails, it hashes the exact binary path supplied by this configuration. The persistent cache still uses a hash of the executable's contents. The Go launcher also sets the bundled SDK's `GOROOT` explicitly, so SDK discovery works without procfs. These changes are precompiled into the checked-in bundle; destination hosts do not build anything.

The `container` profile sets `GOMAXPROCS=1` and Go build parallelism `-p=1`. Its patched gopls permits one Go command at a time across workspace discovery and indexing. `GOMEMLIMIT` defaults to a soft 256 MiB target for Go programs. Node and Tokio worker pools are reduced, and TypeScript uses one semantic tsserver without a separate syntax server. On Linux, a supplied static launcher narrows the server's inherited CPU affinity to one permitted CPU before starting it; PHPantom's manually created indexing pools consequently see one CPU too. If the kernel refuses that operation, the server does not start. Other profiles retain their normal concurrency. The same execution settings apply to the doctor and ordinary language-server launches.

The prebuilt Linux PHP server also caps Tokio at one async worker and four blocking workers in container mode. This separate blocking pool can grow even with one CPU; the cap prevents the late thread burst found during testing. Its normal defaults remain available in the other profiles.

Container VCS actions use one Git index/pack worker and disable automatic Git maintenance for those commands, keeping background Git work out of the shared allowance.

Container Vim also keeps one language-server family active at a time. Switching from PHP to Go, for example, shuts down PHP before starting Go; JavaScript and TypeScript share a family. Switching back can require indexing again. Unsaved buffers stay in Vim and are sent from memory when their server restarts. PHP receives a timed TERM fallback if its shutdown stalls; the next family still waits for confirmed exit. If another server is still stopping, re-enter the buffer to retry. Other profiles keep their usual concurrent servers.

These settings reduce fan-out; they do not impose a kernel process/thread cap or a hard memory limit. WP Cloud sessions have a [25-process and 1 GB memory allowance](https://wp.cloud/wp-cloud-technical-details/wpcloud-site-ssh-and-sftp/), shared by the shell, editor and helpers; the user's container also counts threads. Run the container doctor from an otherwise idle SSH session with Vim closed. Exiting Vim frees its helpers.

## Large PHP files

The target baseline is handwritten PHP around **500 KB and 15,000 lines**, with completion/navigation enabled. There is no 100 KB or 10,000-line cutoff. Syntax is bounded to the first 8,000 columns of each line, expensive UI extras are off, and diagnostic rendering is capped at 100 messages per file. Per-line syntax bounds may reduce colouring beyond that column.

An 8 MiB / 100,000-line threshold enables an explicit visible fast mode: syntax and LSP attachment for that buffer are paused. F1 → Toggle fast mode restores them or lets you opt in earlier. This does not stop a server independently indexing a file from the workspace; its indexing scope is configured separately. Copy `local.vim.example` to ignored `local.vim` to change thresholds. Performance results and their limits are recorded in [VALIDATION.md](VALIDATION.md).

## Exclusions on Work Sandbox

Only Work Sandbox needs the `/nfs` policy. All configuration-supplied language servers, file discovery, VCS commands and table-query jobs use `bin/helper-run`. It creates a private filesystem view before launching the helper and fails closed if the required namespaces/mounts cannot be created. Other symlinks remain usable. `wp-content/blogs.dir` is also pruned by name before file-picker traversal. Exclusions are not inferred from `.gitignore`.

The initial namespace probe is weaker than the actual launcher: run `bin/vim-config-doctor --profile sandbox --lsp` on the real Sandbox. A Linux VM fixture test establishes launcher behavior, not compatibility with every host policy. See [VALIDATION.md](VALIDATION.md) for the precise verified boundary and remaining host checks.

`local.vim` can set `g:vimconfig_denied_paths` to additional normalized absolute directory paths. `/nfs` remains mandatory in the `sandbox` profile. Setting hard exclusions on another profile prevents helper startup: it cannot silently claim enforcement there. Use Sandbox for projects needing hard exclusions. File-picker name exclusions use `g:vimconfig_exclude_names`. Project-specific configuration is deliberately not auto-executed from an arbitrary repository.

## Git, SVN and data

F1 provides async status, diff, history, blame, add, commit draft and submit actions. Git commit uses the staged index. SVN commit is bounded to the selected file. SVN history/blame/submission may contact its repository only when explicitly invoked. These actions use existing host `git`, `svn`, and `diff`; they do not install them. No automatic recursive VCS polling runs while typing.

Rainbow CSV provides CSV/TSV colours, column identification and manual validation. Queries use JavaScript RBQL, run asynchronously over a private snapshot, and open results separately. Delimiter selection is available through F1. Full validation and queries intentionally scan the input when requested. `servers.dat` retains the dedicated syntax and status information from `apokalyptik/vim-servers-dot-dat`. Fugitive and Signify are bundled as optional packages but are not loaded: their automatic subprocesses would bypass the guarded launcher.

## Diagnostics and maintenance

`bin/vim-config-doctor --quick` tests actual executable startup. `--lsp` additionally exercises language-server communication with temporary fixture files; no Python is required on the destination. Failed LSP probes print the response or protocol error, process status, elapsed time, and bounded server stderr to help distinguish a rejected syscall, cache error, or timeout. F1 → Health shows paths/profile inside Vim. Use `:messages` for server startup errors.

The doctor uses a temporary home, workspaces and caches, with Go telemetry disabled for those probes. Ordinary gopls sessions put their persistent index in ignored `.state/cache/gopls`; set `GOPLSCACHE` to override it. Other runtime caches retain their usual locations. Container Go uses the standard package driver, disables background vulnerability scans, and on Linux uses a private telemetry-off config under `.state/container-config` to avoid another Go process; its existing Go env file is preserved through `GOENV`. Other profiles follow the user's telemetry mode; `go telemetry off` disables collection and uploading. `GOTELEMETRY` is a read-only reporting variable, so exporting `GOTELEMETRY=off` does not change that mode. See [Go's telemetry documentation](https://go.dev/doc/telemetry).

The installer and file finder are Bash scripts; no custom Perl helper is used. For maintainers, `python3 tools/prepare-bundle.py --verify` checks included payloads and that the Bash-readable `tools/payloads.tsv` matches the JSON manifest. `--rebuild` is an explicit online preparation operation on a build-capable machine, not part of installation. `--rebuild-gopls` rebuilds only the two gopls archives; add `--offline --work-dir DIR` when that preparation directory already has the pinned Go module cache. `--rebuild-affinity` rebuilds the Linux resource launcher; `--rebuild-phpantom` prepares the patched static Linux PHP server with pinned Rust/Zig inputs. Downstream patches are reapplied by the corresponding scripts under `tools/`.
