#!/usr/bin/env bash
# Bash 3.2 compatible. Run through helper-run for filesystem exclusions.
set -eu

if [[ $# -lt 1 || -z $1 ]]; then
    printf '%s\n' 'find-files: missing root' >&2
    exit 64
fi
root=$1
shift
excluded_names=('' "$@")
denied_paths=('')
while IFS= read -r denied || [[ -n $denied ]]; do
    [[ -z $denied ]] || denied_paths+=("$denied")
done <<< "${VIM_CONFIG_DENY_PATHS-}"

allowed() {
    local candidate=$1 denied
    for denied in "${denied_paths[@]}"; do
        [[ -n $denied ]] || continue
        case "$candidate" in "$denied"|"$denied"/*) return 1 ;; esac
    done
    if [[ ${VIM_CONFIG_PROFILE-} == sandbox ]]; then
        case "$candidate" in */wp-content/blogs.dir|*/wp-content/blogs.dir/*) return 1 ;; esac
    fi
    return 0
}

case "$root" in
    *$'\r'*|*$'\n'*|*$'\t'*) printf '%s\n' 'find-files: root contains an unsupported control character' >&2; exit 64 ;;
    /*) ;;
    *) root=$PWD/$root ;;
esac
if ! allowed "$root"; then printf '%s\n' 'find-files: excluded root' >&2; exit 77; fi
root=$(CDPATH='' cd -P -- "$root" && pwd -P)
case "$root" in
    *$'\r'*|*$'\n'*|*$'\t'*) printf '%s\n' 'find-files: root contains an unsupported control character' >&2; exit 64 ;;
esac
if ! allowed "$root"; then printf '%s\n' 'find-files: excluded root' >&2; exit 77; fi

# Root discovery, including marker metadata checks, happens inside helper-run.
candidate=$root
while [[ $candidate != / ]]; do
    if [[ -d $candidate/.git || -f $candidate/.git || -d $candidate/.svn ||
          -f $candidate/wp-config.php || -f $candidate/composer.json || -f $candidate/go.mod ]]; then
        root=$candidate
        break
    fi
    candidate=${candidate%/*}
    [[ -n $candidate ]] || candidate=/
done
printf 'ROOT\t%s\n' "$root"

# find's compiled traversal detects directory-symlink cycles without running a
# stat subprocess per directory. NUL framing preserves spaces/metacharacters.
# Its -name/-path operands are patterns, so quote configured literal names.
escape_pattern() {
    escaped=$1
    escaped=${escaped//\\/\\\\}
    escaped=${escaped//\*/\\*}
    escaped=${escaped//\?/\\?}
    escaped=${escaped//\[/\\[}
    escaped=${escaped//\]/\\]}
}
prune=('(' '-name' $'*\r*' '-o' '-name' $'*\n*' '-o' '-name' $'*\t*')
for name in "${excluded_names[@]}"; do
    [[ -n $name ]] || continue
    escape_pattern "$name"
    prune+=('-o' '-name' "$escaped")
done
for denied in "${denied_paths[@]}"; do
    [[ -n $denied ]] || continue
    escape_pattern "$denied"
    prune+=('-o' '-path' "$escaped" '-o' '-path' "$escaped/*")
done
if [[ ${VIM_CONFIG_PROFILE-} == sandbox ]]; then
    prune+=('-o' '-path' '*/wp-content/blogs.dir')
fi
prune+=(')' '-prune' '-o' '-type' 'f' '-print0')

find_errors() {
    local line
    while IFS= read -r line || [[ -n $line ]]; do
        case "$line" in
            *'File system loop detected'*|*'directory causes a cycle'*|*'Broken pipe'*) ;;
            *) printf '%s\n' "$line" >&2 ;;
        esac
    done
}

errors=$(mktemp "${TMPDIR:-/tmp}/vim-find-errors.XXXXXXXX")
finder_pid=
cleanup() {
    if [[ -n $finder_pid ]]; then
        kill -TERM "$finder_pid" 2>/dev/null || :
        wait "$finder_pid" 2>/dev/null || :
    fi
    rm -f -- "$errors"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
exec 3< <(LC_ALL=C find -L "$root" "${prune[@]}" 2> "$errors")
finder_pid=$!
count=0
while IFS= read -r -d '' path <&3; do
    if [[ $root == / ]]; then relative=${path#/}; else relative=${path#"$root"/}; fi
    printf '%s\n' "$relative"
    count=$((count + 1))
    [[ $count -lt 20000 ]] || break
done
exec 3<&-
if [[ $count -ge 20000 ]]; then kill -TERM "$finder_pid" 2>/dev/null || :; fi
wait "$finder_pid" 2>/dev/null || :
finder_pid=
find_errors < "$errors"
