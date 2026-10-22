#!/bin/sh
set -eu
test_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
cd "$test_root"
vim_test=${VIM_TEST_BIN:-vim}
mkdir -p .state/tests
for test_script in tests/test-vcs.vim tests/test-ui.vim tests/test-lsp-client.vim; do
    log=".state/tests/$(basename "$test_script").log"
    config=vimrc
    if [ "$test_script" = tests/test-vcs.vim ]; then config=NONE; fi
    if ! VIM_CONFIG_PROFILE=misc "$vim_test" -Nu "$config" -i NONE -n -es -S "$test_script" >"$log" 2>&1; then
        cat "$log"
        printf 'FAIL: %s\n' "$test_script" >&2
        exit 1
    fi
    printf 'PASS: %s\n' "$test_script"
done
tests/test-helper-run.sh
bash tests/test-setup.sh
bash tests/test-find-files.sh
for script in bin/setup libexec/find-files.bash; do
    bash -n "$script"
done
for script in bin/vim-config bin/language-server bin/helper-run bin/vim-config-doctor libexec/helper-run-inner; do
    sh -n "$script"
done
python3 tools/prepare-bundle.py --verify
python3 tests/lsp-smoke.py
