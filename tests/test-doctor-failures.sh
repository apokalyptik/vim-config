#!/usr/bin/env bash
# Exercise real Vim job/channel callbacks against disposable failing servers.
set -eu
test_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
test_vim=${VIM_TEST_BIN:-vim}
fixture=$(mktemp -d "${TMPDIR:-/tmp}/vim-doctor-failures.XXXXXXXX")
fixture=$(CDPATH='' cd -- "$fixture" && pwd -P)
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
mkdir -p "$fixture/root/bin" "$fixture/root/libexec" "$fixture/root/.state/tools/fixture/bin" "$fixture/root/.state/tools/fixture/go/bin"
: > "$fixture/root/.state/tools/fixture/bin/gopls-low-resource"
cp "$test_root/bin/helper-run" "$fixture/root/bin/helper-run"
cp "$test_root/libexec/resource-env.sh" "$fixture/root/libexec/resource-env.sh"
cat > "$fixture/root/.state/tools/fixture/go/bin/go" <<'EOF'
#!/bin/sh
printf 'go fixture\n'
EOF
cat > "$fixture/root/.state/tools/fixture/bin/gopls" <<'EOF'
#!/usr/bin/env bash
if [[ ${1-} == version ]]; then printf 'gopls fixture\n'; exit 0; fi
if [[ -n ${TEST_DOCTOR_INIT_SENTINEL-} ]]; then : > "$TEST_DOCTOR_INIT_SENTINEL"; fi
case "$TEST_DOCTOR_SCENARIO" in
    exited)
        printf 'fixture startup failed\n' >&2
        printf 'final stderr fixture line\n' >&2
        exit 23
        ;;
    error_reply)
        IFS= read -r first_header || :
        body='{"jsonrpc":"2.0","id":1,"error":{"code":-32603,"message":"fixture initialize rejected"}}'
        printf 'Content-Length: %s\r\n\r\n%s' "${#body}" "$body"
        exit 0
        ;;
    after_initialize)
        IFS= read -r first_header || :
        body='{"jsonrpc":"2.0","id":1,"result":{"capabilities":{}}}'
        printf 'Content-Length: %s\r\n\r\n%s' "${#body}" "$body"
        printf 'fixture crash immediately after initialize\n' >&2
        exit 31
        ;;
    malformed)
        IFS= read -r first_header || :
        printf 'not-lsp\r\n\r\n'
        printf 'fixture malformed protocol detail\n' >&2
        exit 0
        ;;
    signaled)
        IFS= read -r first_header || :
        printf 'fixture before TERM\n' >&2
        kill -TERM "$$"
        ;;
    silent)
        trap 'exit 0' TERM
        while :; do IFS= read -r -t 1 pending || :; done
        ;;
    verbose)
        printf 'fixture verbose first line\n' >&2
        for ((index=0; index<10000; index++)); do printf X >&2; done
        printf '\nfixture beyond capture bound\n' >&2
        exit 29
        ;;
    *) exit 64 ;;
esac
EOF
chmod +x "$fixture/root/bin/helper-run" "$fixture/root/.state/tools/fixture/bin/gopls" "$fixture/root/.state/tools/fixture/go/bin/go"
cat > "$fixture/driver.vim" <<'EOF'
let g:vimconfig_doctor_initialize_timeout = $TEST_DOCTOR_SCENARIO ==# 'silent' ? 0.08 : 2
execute 'source ' . fnameescape($VIM_DOCTOR_SOURCE)
EOF

for scenario in exited error_reply after_initialize malformed signaled silent verbose; do
    mkdir "$fixture/$scenario"
    if VIM_DOCTOR_ROOT="$fixture/root" VIM_DOCTOR_PLATFORM=fixture VIM_DOCTOR_MODE=lsp \
        VIM_DOCTOR_PROFILE=container VIM_DOCTOR_TEMP="$fixture/$scenario" \
        VIM_DOCTOR_SOURCE="$test_root/libexec/vim-config-doctor.vim" \
        VIM_CONFIG_DENY_PATHS='' TEST_DOCTOR_SCENARIO="$scenario" \
        "$test_vim" -Nu NONE -i NONE -n -es -S "$fixture/driver.vim" > "$fixture/$scenario/vim.log" 2>&1; then
        printf 'FAIL: doctor accepted failing fixture %s\n' "$scenario" >&2; exit 1
    fi
    report=$fixture/$scenario/report
    if [[ $scenario == after_initialize ]]; then
        grep -F 'PASS: gopls LSP initialize in a temporary workspace' "$report" >/dev/null
        grep -F 'FAIL: gopls ' "$report" >/dev/null
    else
        grep -F 'FAIL: gopls LSP initialize in a temporary workspace' "$report" >/dev/null
    fi
    grep -F '  Wait: ' "$report" >/dev/null
    grep -F '  Job: status=' "$report" >/dev/null
    grep -F '  Fixture response' "$report" >/dev/null
    if grep -F 'doctor probe exception' "$report" >/dev/null; then
        cat "$report" >&2
        printf 'FAIL: fixture escaped per-probe diagnostics: %s\n' "$scenario" >&2; exit 1
    fi
done
grep -F 'status=dead, exit=23' "$fixture/exited/report" >/dev/null
grep -Fx '    fixture startup failed' "$fixture/exited/report" >/dev/null
grep -Fx '    final stderr fixture line' "$fixture/exited/report" >/dev/null
grep -F '"code":-32603' "$fixture/error_reply/report" >/dev/null
grep -F 'fixture initialize rejected' "$fixture/error_reply/report" >/dev/null
grep -F 'status=dead, exit=31' "$fixture/after_initialize/report" >/dev/null
grep -F 'fixture crash immediately after initialize' "$fixture/after_initialize/report" >/dev/null
grep -F 'invalid LSP framing' "$fixture/malformed/report" >/dev/null
grep -F 'Unparsed stdout: not-lsp' "$fixture/malformed/report" >/dev/null
grep -E 'signal=[Tt][Ee][Rr][Mm]' "$fixture/signaled/report" >/dev/null
grep -F 'Wait: timeout' "$fixture/silent/report" >/dev/null
grep -F 'status=run, exit=unavailable' "$fixture/silent/report" >/dev/null
grep -F 'limit 0.08s' "$fixture/silent/report" >/dev/null
grep -F 'fixture verbose first line' "$fixture/verbose/report" >/dev/null
grep -F 'stderr bytes omitted]' "$fixture/verbose/report" >/dev/null
[[ $(wc -c < "$fixture/verbose/report") -lt 7000 ]]
rm "$fixture/root/.state/tools/fixture/bin/gopls-low-resource"
mkdir "$fixture/old-tools"
if VIM_DOCTOR_ROOT="$fixture/root" VIM_DOCTOR_PLATFORM=fixture VIM_DOCTOR_MODE=lsp \
    VIM_DOCTOR_PROFILE=container VIM_DOCTOR_TEMP="$fixture/old-tools" \
    VIM_DOCTOR_SOURCE="$test_root/libexec/vim-config-doctor.vim" \
    VIM_CONFIG_DENY_PATHS='' TEST_DOCTOR_SCENARIO=exited \
    TEST_DOCTOR_INIT_SENTINEL="$fixture/old-tools/initialized" \
    "$test_vim" -Nu NONE -i NONE -n -es -S "$fixture/driver.vim" > "$fixture/old-tools/vim.log" 2>&1; then
    printf '%s\n' 'FAIL: doctor accepted legacy container Go tools' >&2; exit 1
fi
grep -F 'Container Go tools need the low-resource build' "$fixture/old-tools/report" >/dev/null
[[ ! -e "$fixture/old-tools/initialized" ]] || { printf '%s\n' 'FAIL: legacy Go LSP initialized before readiness refusal' >&2; exit 1; }
printf '%s\n' 'doctor failure tests: PASS (exit/stderr, error reply, post-initialize exit, malformed framing, signal, timeout, bounded readable trace)'
