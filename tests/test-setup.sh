#!/bin/bash
# Small offline fixtures exercise the real installer, including its rollback.
set -euo pipefail
test_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
test_tmp=$(mktemp -d "${TMPDIR:-/tmp}/vim-config-setup.XXXXXXXX")
trap 'rm -rf "$test_tmp"' EXIT
fail() { printf 'FAIL: setup: %s\n' "$*" >&2; exit 1; }
fixture="$test_tmp/checkout with spaces"
mkdir -p "$fixture/bin" "$fixture/tools" "$fixture/payloads" "$fixture/doc" "$test_tmp/input/bin" "$test_tmp/host-bin" "$test_tmp/home"
cp "$test_root/bin/setup" "$fixture/bin/setup"
printf 'new tool\n' > "$test_tmp/input/bin/tool"
tar -czf "$fixture/payloads/platform.tar.gz" -C "$test_tmp/input" bin
tar -czf "$fixture/payloads/shared.tar.gz" -C "$test_tmp/input" bin
cp "$fixture/payloads/shared.tar.gz" "$test_tmp/good-shared.tar.gz"
openssl_bin=$(command -v openssl)
fixture_digest=$("$openssl_bin" dgst -sha256 "$fixture/payloads/platform.tar.gz")
fixture_digest=${fixture_digest##* }
shared_digest=$("$openssl_bin" dgst -sha256 "$fixture/payloads/shared.tar.gz")
shared_digest=${shared_digest##* }
printf '# vim-config payloads v1\nplatform\tlinux-x86_64\tpayloads/platform.tar.gz\t%s\tlinux-x86_64\t0\nshared\tall\tpayloads/shared.tar.gz\t%s\tshared\t0\n' "$fixture_digest" "$shared_digest" > "$fixture/tools/payloads.tsv"
cp "$fixture/tools/payloads.tsv" "$test_tmp/good.tsv"
# This PATH deliberately contains neither Perl nor Python, nor sha256sum, so
# setup must use the OpenSSL checksum backend and the checked-in TSV.
for tool in dirname uname mkdir mktemp rm mv tar gzip ln date; do
    ln -s "$(command -v "$tool")" "$test_tmp/host-bin/$tool"
done
ln -s "$openssl_bin" "$test_tmp/host-bin/openssl"
printf '#!/bin/sh\nexit 0\n' > "$test_tmp/host-bin/vim"
chmod +x "$test_tmp/host-bin/vim"
run_setup() {
    PATH="$test_tmp/host-bin" HOME="$test_tmp/home" /bin/bash "$fixture/bin/setup" --platform linux-x86_64 "$@" > "$test_tmp/output" 2>&1
}
run_setup --profile container || { cat "$test_tmp/output"; fail 'fresh setup'; }
[[ $(cat "$fixture/.state/tools/linux-x86_64/bin/tool") == 'new tool' ]] || fail 'platform extraction'
[[ $(cat "$fixture/.state/tools/shared/bin/tool") == 'new tool' ]] || fail 'shared extraction'
[[ $(cat "$fixture/.state/profile") == container ]] || fail 'profile'
[[ ! -e "$test_tmp/home/.vimrc" ]] || fail 'unexpected home change'
printf 'old platform\n' > "$fixture/.state/tools/linux-x86_64/bin/tool"
printf 'old shared\n' > "$fixture/.state/tools/shared/bin/tool"
# A bad archive must fail without replacing either installed tree or profile.
printf 'corruption' >> "$fixture/payloads/shared.tar.gz"
if run_setup --profile misc; then fail 'accepted checksum mismatch'; fi
[[ $(cat "$fixture/.state/tools/linux-x86_64/bin/tool") == 'old platform' ]] || fail 'checksum failure changed tools'
[[ $(cat "$fixture/.state/profile") == container ]] || fail 'checksum failure changed profile'
cp "$test_tmp/good-shared.tar.gz" "$fixture/payloads/shared.tar.gz"
# Make the replacement of the second tree fail once, after the first moved.
mv_bin=$(command -v mv)
rm "$test_tmp/host-bin/mv"
cat > "$test_tmp/host-bin/mv" <<'SCRIPT'
#!/bin/bash
case "$1:$2" in */unpack.*/shared:*/tools/shared) exit 1 ;; esac
exec "$VIM_SETUP_TEST_MV" "$@"
SCRIPT
chmod +x "$test_tmp/host-bin/mv"
export VIM_SETUP_TEST_MV="$mv_bin"
if run_setup --profile misc; then fail 'injected install failure ignored'; fi
[[ $(cat "$fixture/.state/tools/linux-x86_64/bin/tool") == 'old platform' ]] || fail 'platform rollback'
[[ $(cat "$fixture/.state/tools/shared/bin/tool") == 'old shared' ]] || fail 'shared rollback'
[[ $(cat "$fixture/.state/profile") == container ]] || fail 'rollback changed profile'
# If restoring a backup itself fails, retain that backup for manual recovery.
cat > "$test_tmp/host-bin/mv" <<'SCRIPT'
#!/bin/bash
case "$1:$2" in */unpack.*/shared:*/tools/shared|*/previous-shared:*/tools/shared) exit 1 ;; esac
exec "$VIM_SETUP_TEST_MV" "$@"
SCRIPT
if run_setup --profile misc; then fail 'injected restore failure ignored'; fi
recovery=("$fixture/.state/"unpack.*/previous-shared)
[[ ${#recovery[@]} -eq 1 && -d "${recovery[0]}" ]] || fail 'lost backup after failed restore'
[[ $(cat "${recovery[0]}/bin/tool") == 'old shared' ]] || fail 'backup contents after failed restore'
"$mv_bin" "${recovery[0]}" "$fixture/.state/tools/shared"
rm -rf "${recovery[0]%/previous-shared}"
rm "$test_tmp/host-bin/mv"
ln -s "$mv_bin" "$test_tmp/host-bin/mv"
printf 'my vimrc\n' > "$test_tmp/home/.vimrc"
run_setup --profile misc --link-home || { cat "$test_tmp/output"; fail 'reinstall with home link'; }
[[ $(cat "$fixture/.state/profile") == misc ]] || fail 'reinstall profile'
[[ -L "$test_tmp/home/.vimrc" ]] || fail 'home link'
[[ $(cat "$test_tmp/home/".vimrc.before-vim-config-*) == 'my vimrc' ]] || fail 'home backup'
if command -v sha256sum >/dev/null 2>&1; then
    ln -s "$(command -v sha256sum)" "$test_tmp/host-bin/sha256sum"
    run_setup --profile wsl || { cat "$test_tmp/output"; fail 'sha256sum backend'; }
fi
if compgen -G "$fixture/.state/unpack.*" >/dev/null; then fail 'staging directory leaked'; fi
printf '%s\n' 'PASS: Bash setup (offline, checksums, rollback, spaces, home backup)'
