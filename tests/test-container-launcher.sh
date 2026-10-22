#!/usr/bin/env bash
# Stale container installations must not start older high-fanout tools.
set -eu
test_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/vim-container-launcher.XXXXXXXX")
fixture=$(CDPATH='' cd -- "$fixture" && pwd -P)
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
fail() { printf 'FAIL: container launcher: %s\n' "$*" >&2; exit 1; }
if [[ ${VIM_TEST_LAUNCHER_FORCE_LINUX-} == 1 ]]; then
    mkdir "$fixture/host-bin"
    cat > "$fixture/host-bin/uname" <<'SCRIPT'
#!/bin/sh
case "$1" in
    -s) printf 'Linux\n' ;;
    -m) printf 'x86_64\n' ;;
    *) exit 1 ;;
esac
SCRIPT
    chmod +x "$fixture/host-bin/uname"
    export PATH="$fixture/host-bin:$PATH"
fi
case "$(uname -s):$(uname -m)" in
    Darwin:arm64) platform=darwin-arm64 ;;
    Linux:x86_64|Linux:amd64) platform=linux-x86_64 ;;
    *) printf '%s\n' 'SKIP: container launcher fixture requires a supported tool platform'; exit 0 ;;
esac
mkdir -p "$fixture/bin" "$fixture/libexec" "$fixture/.state/tools/$platform/bin" "$fixture/.state/tools/$platform/go"
cp "$test_root/bin/language-server" "$test_root/bin/helper-run" "$fixture/bin/"
cp "$test_root/libexec/resource-env.sh" "$fixture/libexec/"
cat > "$fixture/.state/tools/$platform/bin/gopls" <<'SCRIPT'
#!/bin/sh
{
    printf 'LOW=%s\n' "${VIM_CONFIG_LOW_RESOURCE-}"
    printf 'GOMAXPROCS=%s\n' "${GOMAXPROCS-}"
    printf 'GOFLAGS=%s\n' "${GOFLAGS-}"
    printf 'GOROOT=%s\n' "${GOROOT-}"
    printf 'EXECUTABLE=%s\n' "${VIM_CONFIG_GOPLS_EXECUTABLE-}"
    printf 'UV=%s\n' "${UV_THREADPOOL_SIZE-}"
    printf 'NODE_OPTIONS=%s\n' "${NODE_OPTIONS-}"
} > "$VIM_TEST_LAUNCHER_OUTPUT"
SCRIPT
chmod +x "$fixture/.state/tools/$platform/bin/gopls"
cp "$fixture/.state/tools/$platform/bin/gopls" "$fixture/.state/tools/$platform/bin/node"
cp "$fixture/.state/tools/$platform/bin/gopls" "$fixture/.state/tools/$platform/bin/phpantom_lsp"
run_launcher() {
    VIM_CONFIG_PROFILE=$1 VIM_CONFIG_DENY_PATHS='' VIM_CONFIG_RESOURCE_POLICY='' VIM_TEST_LAUNCHER_OUTPUT="$fixture/executed" \
        GOMAXPROCS=99 GOFLAGS='-trimpath' UV_THREADPOOL_SIZE=99 NODE_OPTIONS='--no-warnings' \
        "$fixture/bin/language-server" "$2" > "$fixture/stdout" 2> "$fixture/stderr"
}
if run_launcher container go; then fail 'legacy gopls was accepted without the low-resource marker';
else [[ $? -eq 69 ]] || fail 'legacy refusal exit status'; fi
[[ ! -e "$fixture/executed" ]] || fail 'legacy binary executed before refusal'
grep -F 'bin/setup --profile container' "$fixture/stderr" >/dev/null || fail 'refusal missing reinstall instruction'
printf 'fixture-low-resource\n' > "$fixture/.state/tools/$platform/bin/gopls-low-resource"
if [[ "$platform" == linux-x86_64 ]]; then
    if run_launcher container go; then fail 'missing resource launcher accepted';
    else [[ $? -eq 69 ]] || fail 'missing resource launcher exit status'; fi
    [[ ! -e "$fixture/executed" ]] || fail 'Go executed without the resource launcher'
    cat > "$fixture/.state/tools/$platform/bin/affinity-exec" <<'SCRIPT'
#!/bin/sh
exec "$@"
SCRIPT
    chmod +x "$fixture/.state/tools/$platform/bin/affinity-exec"
fi
run_launcher container go || fail 'current container gopls launch'
grep -Fx 'LOW=1' "$fixture/executed" >/dev/null || fail 'container profile flag'
grep -Fx 'GOMAXPROCS=1' "$fixture/executed" >/dev/null || fail 'Go scheduler concurrency'
grep -F ' -p=1' "$fixture/executed" >/dev/null || fail 'Go build concurrency'
grep -Fx "GOROOT=$fixture/.state/tools/$platform/go" "$fixture/executed" >/dev/null || fail 'relocated GOROOT'
grep -Fx "EXECUTABLE=$fixture/.state/tools/$platform/bin/gopls" "$fixture/executed" >/dev/null || fail 'executable fallback identity'
run_launcher container typescript || fail 'container TypeScript launch'
grep -Fx 'UV=1' "$fixture/executed" >/dev/null || fail 'Node libuv pool'
grep -Fx 'NODE_OPTIONS=--no-warnings --v8-pool-size=1' "$fixture/executed" >/dev/null || fail 'inherited Node options/pool'
VIM_CONFIG_DENY_PATHS='' VIM_CONFIG_RESOURCE_POLICY='' VIM_TEST_LAUNCHER_OUTPUT="$fixture/executed" \
    GOMAXPROCS=99 GOFLAGS='-trimpath' UV_THREADPOOL_SIZE=99 NODE_OPTIONS='--no-warnings' \
    "$fixture/bin/helper-run" --profile container -- "$fixture/.state/tools/$platform/bin/node"
grep -Fx 'GOMAXPROCS=1' "$fixture/executed" >/dev/null || fail 'direct helper scheduler cap'
grep -Fx 'UV=1' "$fixture/executed" >/dev/null || fail 'direct helper Node cap'
grep -Fx 'NODE_OPTIONS=--no-warnings --v8-pool-size=1' "$fixture/executed" >/dev/null || fail 'direct helper Node option duplication'
# A non-container transition clears the marker so the next container launch
# appends its own flags instead of trusting an inherited stale marker.
VIM_TEST_LAUNCHER_OUTPUT="$fixture/executed" VIM_CONFIG_RESOURCE_POLICY=container-v1 \
    VIM_TEST_RESOURCE_ENV="$fixture/libexec/resource-env.sh" \
    VIM_TEST_RESOURCE_BINARY="$fixture/.state/tools/$platform/bin/node" \
    sh -c '. "$VIM_TEST_RESOURCE_ENV"; vim_config_set_resources misc; NODE_OPTIONS=--no-warnings; export NODE_OPTIONS; vim_config_set_resources container; exec "$VIM_TEST_RESOURCE_BINARY"'
grep -Fx 'NODE_OPTIONS=--no-warnings --v8-pool-size=1' "$fixture/executed" >/dev/null || fail 'profile transition retained stale policy marker'
if [[ "$platform" == linux-x86_64 ]]; then
    rm "$fixture/executed"
    if run_launcher container php; then fail 'legacy PHP accepted without the low-resource marker';
    else [[ $? -eq 69 ]] || fail 'legacy PHP refusal exit status'; fi
    [[ ! -e "$fixture/executed" ]] || fail 'legacy PHP binary executed before refusal'
    grep -F 'update the container PHP tools' "$fixture/stderr" >/dev/null || fail 'PHP refusal missing reinstall instruction'
    printf 'fixture-low-resource\n' > "$fixture/.state/tools/$platform/bin/phpantom-low-resource"
    run_launcher container php || fail 'current container PHP launch with resource launcher'
    grep -Fx 'LOW=1' "$fixture/executed" >/dev/null || fail 'container PHP resource flag'
    rm "$fixture/.state/tools/$platform/bin/phpantom-low-resource"
fi
run_launcher misc php || fail 'unrestricted PHP unnecessarily required the container marker'
grep -Fx 'LOW=0' "$fixture/executed" >/dev/null || fail 'unrestricted PHP resource flag'
rm "$fixture/.state/tools/$platform/bin/gopls-low-resource"
run_launcher misc go || fail 'unrestricted profile unnecessarily required container marker'
grep -Fx 'LOW=0' "$fixture/executed" >/dev/null || fail 'unrestricted profile flag'
grep -Fx 'GOMAXPROCS=99' "$fixture/executed" >/dev/null || fail 'unrestricted profile changed scheduler'
printf 'PASS: container launcher %s (legacy Go/PHP guards, tool paths, resource policy, Node inheritance)\n' "$platform"
# These launchers execute only shell fixtures, so exercise the Linux-only
# guards on a macOS test host as well without running any foreign binaries.
if [[ "$platform" == darwin-arm64 ]]; then
    VIM_TEST_LAUNCHER_FORCE_LINUX=1 bash "$test_root/tests/test-container-launcher.sh"
fi
