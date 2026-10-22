# Third-party software

This checkout vendors source plugins and prepared language-server/runtime archives
for offline installation. The versions, source URLs, source revisions, upstream
checksums, archive checksums, and executable paths are recorded in
[`tools/vendor-manifest.json`](tools/vendor-manifest.json). The JavaScript package
lock records the exact transitive packages and their registry integrity values.
No paid server, account activation, or licence-key prompt is included.

Retain this file and the corresponding licence texts when redistributing the
bundle. The individual upstream licences govern their respective components.

| Component | Version or revision | Licence and retained notices |
| --- | --- | --- |
| [yegappan/lsp](https://github.com/yegappan/lsp) | `c741b2f1afb42b9f267824dac4049674908f4a41` | MIT; `vendor/pack/vim-config/start/lsp/LICENSE` |
| [vim-fugitive](https://github.com/tpope/vim-fugitive) | `3b753cf8c6a4dcde6edee8827d464ba9b8c4a6f0` | Same terms as Vim, as stated in `vendor/pack/vim-config/opt/fugitive/doc/fugitive.txt`; full terms in `vendor/licenses/vim-license.txt` |
| [vim-signify](https://github.com/mhinz/vim-signify) | `e7557022f94270e887cbb391a746c1818e570d7f` | MIT; `vendor/pack/vim-config/opt/signify/LICENSE` |
| [Rainbow CSV and RBQL](https://github.com/mechatroner/rainbow_csv) | `3dbbfd7d17536aebfb80f571255548495574c32b` | MIT; `vendor/pack/vim-config/start/rainbow_csv/LICENSE` and `rbql_core/LICENSE` |
| [vim-servers-dot-dat](https://github.com/apokalyptik/vim-servers-dot-dat) | `23dfc234f358353d1ae4b8866ac26bfa8cdaea04` | MIT; `vendor/pack/vim-config/start/servers-dot-dat/LICENSE` |
| [PHPantom](https://github.com/PHPantom-dev/phpantom_lsp) | `0.11.1` | MIT; `vendor/licenses/phpantom-MIT.txt`. Rust dependency notices in `vendor/licenses/phpantom-dependencies/`, with inherited workspace notices in `vendor/licenses/phpantom-upstream/`. The corresponding lock, source checksums, crate metadata, and source revisions are retained alongside them. |
| [JetBrains phpstorm-stubs](https://github.com/JetBrains/phpstorm-stubs) embedded in PHPantom | `5f68c1021badebe34119fb8fa10ba7cc25de6c0c` | Apache-2.0; `vendor/licenses/phpstorm-stubs-Apache-2.0.txt`, pin and checksum in `vendor/licenses/phpantom-stubs.lock` |
| [Node.js](https://nodejs.org/) | `24.22.1` LTS | MIT and its bundled dependency terms; complete upstream `LICENSE` in `vendor/licenses/node-LICENSE.txt` and each Node archive |
| [GCC runtime libraries](https://gcc.gnu.org/onlinedocs/libstdc++/manual/license.html), private Linux Node dependencies | Debian `12.2.0-14+deb12u1` | GPL-3.0 with GCC Runtime Library Exception 3.1; `vendor/licenses/gcc-runtime/{Debian-copyright,COPYING3,COPYING.RUNTIME}`. Exact Debian package URLs and checksums are recorded in the manifest. |
| [Go](https://go.dev/) SDK | `1.27.3` | BSD-style licence and third-party terms in the unmodified SDK archives; root licence and patent grant also in `vendor/licenses/go-LICENSE.txt` and `go-PATENTS.txt` |
| [gopls](https://go.dev/gopls/) | `0.24.0+vim-config.1`, based on upstream `0.24.0` | BSD-style licence; full module dependency notices in `vendor/licenses/gopls-dependencies/`. Builds use the official Go SDK with `CGO_ENABLED=0`. The small executable-discovery fallback is documented in `vendor/licenses/gopls-downstream-patch.md` and reproduced by `tools/patch-gopls.py`. |
| [typescript-language-server](https://github.com/typescript-language-server/typescript-language-server) | `6.0.2` | Apache-2.0; `vendor/licenses/javascript-dependencies/typescript-language-server/LICENSE` |
| [TypeScript](https://github.com/microsoft/TypeScript) | `6.0.3` | Apache-2.0; `vendor/licenses/javascript-dependencies/typescript/LICENSE.txt` and `ThirdPartyNoticeText.txt` |
| [vscode-langservers-extracted](https://github.com/hrsh7th/vscode-langservers-extracted) | `4.10.0` | MIT; `vendor/licenses/javascript-dependencies/vscode-langservers-extracted/LICENSE` |

All JavaScript dependency metadata is indexed in
`vendor/licenses/javascript-dependencies.json`; complete licence and notice files
also remain inside `payloads/javascript-language-servers.tar.gz`. Unused upstream
ESLint and Markdown entrypoints may be present in that distribution, but the
configured bundle uses its HTML, CSS, and JSON servers.

PHPantom's complete Cargo lock contains dependencies for several operating
systems and build/test configurations. Their preserved notices are a superset
of those linked into either shipped binary. Where a dependency offers a choice
of licences, the permissive alternative is used for this redistribution.
`vendor/licenses/phpantom-upstream-sources.json` identifies workspace crates whose
published archives omit inherited licence files and points to the exact source
revision from which the notices were recovered.

## Prepared archive details

The Linux PHPantom release uses static musl linkage despite the historical
`unknown-linux-gnu` name of its upstream asset. The Linux gopls build disables
CGO and is statically linked. The Node.js binaries are official platform builds;
they are not claimed to be statically linked. macOS programs use normal operating
system libraries. Shipping a binary does not establish compatibility with a
host's syscall policy; target-host health checks remain necessary.

Node archives retain the executable and its complete upstream licence text,
without npm. The Linux archive also contains private `libstdc++.so.6` and
`libgcc_s.so.1` from Debian 12, together with their complete retained licence
texts. Its `bin/node` launcher selects those libraries only for the Node process
and executes the unmodified official binary at `bin/node.real`. It requires the
host's normal glibc loader and glibc 2.36 or newer; the private C++ runtime avoids
requiring installation of those two packages. The Go SDK archives are unmodified official distributions. The
JavaScript dependency tree is installed during bundle preparation with scripts
disabled, then compressed. TypeScript 6 is intentionally pinned because it retains
the JavaScript `tsserver.js` used by the selected language server; TypeScript 7's
native packaging is not substituted implicitly.

Maintainers can verify committed archives with:

```sh
python3 tools/prepare-bundle.py --verify
```

`--rebuild` is a separate, explicit maintainer operation that uses the network,
npm, and the downloaded Go toolchain. Normal installation does none of those
things. Downstream LSP client changes are reapplied by `tools/patch-lsp.py` after
fetching the pinned upstream source.
