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
| `container` | Restricted Work Containers | Direct execution; uploaded runtimes must pass the doctor's real execution tests |
| `sandbox` | Work Sandbox with `blogs.dir → /nfs` | Isolated helper filesystem; `/nfs` is hidden; failure prevents the helper from starting |
| `misc` | Work Misc Hosts | Direct execution |
| `laptop` | macOS ARM64 | Direct execution |
| `wsl` | Home Windows through Linux x86-64 WSL | Direct execution |

Setup uses Bash (including macOS's bundled Bash 3.2), tar, and either `sha256sum` or `openssl`. It verifies and unpacks only the current platform plus shared JavaScript servers into ignored `.state/tools`. About 284 MiB of compressed payloads are checked in for both platforms; unpacking a platform needs considerably more space. Setup writes inside this checkout. It does not alter your existing Vim configuration unless you explicitly add `--link-home`; that option backs up `~/.vimrc` before linking this configuration.

Use `./bin/vim-config --profile container file.php` for a one-off profile override. Keep the checkout at its installed location when using the home symlink. Re-run setup after updating the checked-out tools. Vim startup never runs setup or downloads tools.

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

`bin/vim-config-doctor --quick` tests actual executable startup. `--lsp` additionally exercises language-server communication with temporary fixture files; no Python is required on the destination. F1 → Health shows paths/profile inside Vim. Use `:messages` for server startup errors. The doctor uses temporary workspaces/caches; ordinary language servers maintain their usual per-user/project caches.

The installer and file finder are Bash scripts; no custom Perl helper is used. For maintainers, `python3 tools/prepare-bundle.py --verify` checks included payloads and that the Bash-readable `tools/payloads.tsv` matches the JSON manifest. `--rebuild` is an explicit online preparation operation on a build-capable machine, not part of installation. The small downstream LSP integration hooks are reapplied by `tools/patch-lsp.py`.
