#!/usr/bin/env bash
# Portable Bash 3.2 tests: real traversal, root discovery, symlinks, pruning/cap.
set -eu
test_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/vim-finder-test.XXXXXXXX")
fixture=$(CDPATH='' cd -- "$fixture" && pwd -P)
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
project=$fixture/project
mkdir -p "$project/.git" "$project/src/nested" "$project/ignored" \
    "$project/denied" "$project/omit[glob]" "$project/omitg" \
    "$project/wp-content" "$fixture/external" "$fixture/nfs-target"
: > "$project/src/nested/normal file.php"
: > "$project/.git/GIT_MARKER"
: > "$project/ignored/EXCLUDED_MARKER.php"
: > "$project/denied/DENIED_MARKER.php"
: > "$project/omit[glob]/EXACT_EXCLUDED_MARKER.php"
: > "$project/omitg/literal-name-pattern-control.php"
: > "$fixture/external/symlink-target.php"
: > "$fixture/nfs-target/BLOGS_DIR_MARKER.php"
: > "$project/"$'tab\tname.php'
: > "$project/"$'cr\rname.php'
mkdir "$project/"$'newline\nname'
: > "$project/"$'newline\nname/WEIRD_PARENT_MARKER.php'
ln -s ../external "$project/allowed-link"
ln -s ../src "$project/src/loop"
ln -s "$fixture/nfs-target" "$project/wp-content/blogs.dir"

VIM_CONFIG_PROFILE=sandbox VIM_CONFIG_DENY_PATHS="$project/denied" \
    bash "$test_root/libexec/find-files.bash" "$project/src/nested" .git ignored 'omit[glob]' \
    > "$fixture/output" 2> "$fixture/errors"
IFS=$'\t' read -r tag discovered_root < "$fixture/output"
[[ $tag == ROOT && $discovered_root == "$project" ]]
for expected in 'src/nested/normal file.php' 'allowed-link/symlink-target.php' 'omitg/literal-name-pattern-control.php'; do
    grep -Fx -- "$expected" "$fixture/output" >/dev/null
done
[[ $(wc -l < "$fixture/output") -eq 4 ]]
if grep -E 'MARKER|tab|crname|newline|src/loop/' "$fixture/output" >/dev/null; then
    printf '%s\n' 'FAIL: excluded/weird/loop path leaked into finder results' >&2; exit 1
fi

# No configured exclusions must also work on Bash 3.2 with nounset enabled.
# Pass the nested directory through the real launcher, leaving discovery to
# the finder instead of computing the repository root in the UI process.
mkdir -p "$fixture/no-exclusions/.git" "$fixture/no-exclusions/nested"
: > "$fixture/no-exclusions/nested/one.php"
VIM_CONFIG_PROFILE=misc VIM_CONFIG_DENY_PATHS='' "$test_root/bin/helper-run" --profile misc -- \
    bash "$test_root/libexec/find-files.bash" "$fixture/no-exclusions/nested" > "$fixture/no-exclusions-output"
IFS=$'\t' read -r tag discovered_root < "$fixture/no-exclusions-output"
[[ $tag == ROOT && $discovered_root == "$fixture/no-exclusions" ]]
grep -Fx 'nested/one.php' "$fixture/no-exclusions-output" >/dev/null
[[ ! -s $fixture/errors ]]
if VIM_CONFIG_DENY_PATHS="$project/denied" bash "$test_root/libexec/find-files.bash" "$project/denied" > "$fixture/denied-output" 2>/dev/null; then
    printf '%s\n' 'FAIL: excluded root accepted' >&2; exit 1
else
    [[ $? -eq 77 && ! -s $fixture/denied-output ]]
fi

# Exercise a real producer exceeding the UI protocol limit; no Python needed.
mkdir -p "$fixture/large/.git"
for ((index=0; index<20003; index++)); do : > "$fixture/large/file-$index.php"; done
bash "$test_root/libexec/find-files.bash" "$fixture/large" .git > "$fixture/capped" 2> "$fixture/capped-errors"
[[ $(wc -l < "$fixture/capped") -eq 20001 ]]
[[ ! -s $fixture/capped-errors ]]
printf '%s\n' 'finder tests: PASS (root protocol, allowed symlink, loop, exact exclusions, weird names, 20,000 cap)'
