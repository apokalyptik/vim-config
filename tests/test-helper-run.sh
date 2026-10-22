#!/bin/sh
# Portable launcher tests. The optional QEMU test verifies Linux mount behavior.
set -eu
test_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
test_tmp=$(mktemp -d "${TMPDIR:-/tmp}/vim-helper-test.XXXXXXXX")
trap 'rm -rf "$test_tmp"' EXIT HUP INT TERM

sh -n "$test_root/bin/helper-run" "$test_root/libexec/helper-run-inner"
for test_profile in container misc laptop wsl; do
    test_output=$("$test_root/bin/helper-run" --profile "$test_profile" -- \
        /bin/sh -c 'printf "%s|%s" "$1" "$2"' test 'a b' '$(not-a-command)')
    [ "$test_output" = 'a b|$(not-a-command)' ]
done
for test_profile in container misc laptop wsl; do
    if VIM_CONFIG_DENY_PATHS=/nfs "$test_root/bin/helper-run" --profile "$test_profile" \
        -- /bin/sh -c 'exit 88' 2>"$test_tmp/error"; then
        printf '%s\n' 'FAIL: hard exclusions silently ignored' >&2; exit 1
    else
        [ "$?" -eq 69 ]
        grep -F 'hard exclusions require sandbox profile' "$test_tmp/error" >/dev/null
    fi
done
if "$test_root/bin/helper-run" --profile container -- /bin/sh -c 'exit 37'; then
    printf '%s\n' 'FAIL: child failure became success' >&2; exit 1
else
    [ "$?" -eq 37 ]
fi
for test_deny in relative / /a/../b /nfs/ /a//b; do
    if VIM_CONFIG_DENY_PATHS="$test_deny" "$test_root/bin/helper-run" \
        --profile sandbox -- /bin/true 2>"$test_tmp/error"; then
        printf '%s\n' 'FAIL: malformed deny path accepted' >&2; exit 1
    else
        [ "$?" -eq 64 ]
    fi
done

mkdir "$test_tmp/mocks"
cat > "$test_tmp/mocks/unshare" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$TEST_LOG"
printf '%s\n' "$VIM_CONFIG_DENY_PATHS" > "$TEST_DENY_LOG"
exit 73
EOF
for test_utility in mount setpriv; do
    printf '#!/bin/sh\nexit 1\n' > "$test_tmp/mocks/$test_utility"
done
chmod +x "$test_tmp/mocks/"*
if PATH="$test_tmp/mocks:$PATH" TEST_LOG="$test_tmp/argv" TEST_DENY_LOG="$test_tmp/deny" \
    VIM_CONFIG_DENY_PATHS='/extra path
/another' "$test_root/bin/helper-run" --profile sandbox -- /bin/true; then
    printf '%s\n' 'FAIL: namespace launcher failure became success' >&2; exit 1
else
    [ "$?" -eq 73 ]
fi
for test_flag in --user --map-root-user --mount --pid --fork --kill-child=KILL --propagation private; do
    grep -Fx -- "$test_flag" "$test_tmp/argv" >/dev/null
done
printf '/nfs\n/extra path\n/another\n' > "$test_tmp/expected-deny"
cmp "$test_tmp/expected-deny" "$test_tmp/deny"
printf '%s\n' 'helper-run portable tests: PASS (argument handling, deny validation, fail-closed dispatch)' \
    'Linux filesystem masking requires tests/qemu-helper.sh or a test on Work Sandbox.'
