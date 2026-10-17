#!/bin/bash
# Pack or unpack the formulae one CI run installed into the Homebrew prefix,
# so a later run on the same image restores them instead of installing again.
#
#   ci_brew_cellar_cache.sh save <archive> <added-list>
#   ci_brew_cellar_cache.sh restore <archive>
#
# <added-list> names one formula per line: the ones this run installed, i.e.
# the diff of `brew list --formula` before and after. For each, the archive
# takes its Cellar directory (the install receipt lives there, which is what
# makes brew count it as installed) and every symlink in the prefix's link
# directories that points into it, so a restore needs no `brew link`.
#
# Only the added formulae, never the whole Cellar: the macOS runner image
# ships ~5 GB of formulae of its own, and an archive that size takes longer
# to restore than the install it replaces.
#
# BREW_PREFIX overrides the prefix (the tests use a fake one).

set -euo pipefail

prefix="${BREW_PREFIX:-/opt/homebrew}"
# Where `brew link` puts symlinks. var/homebrew/linked is brew's own record of
# what is linked; without it brew reports a restored formula as unlinked.
link_dirs=(bin sbin lib include share etc opt var/homebrew/linked)

usage() {
    echo "usage: $0 save <archive> <added-list> | restore <archive>" >&2
    exit 2
}

save() {
    local archive="$1" added="$2"
    local names=()
    while IFS= read -r name; do
        [ -n "$name" ] && names+=("$name")
    done <"$added"
    if [ "${#names[@]}" -eq 0 ]; then
        echo "nothing to save: $added lists no formulae" >&2
        return 1
    fi

    local list
    list=$(mktemp)
    local name d
    for name in "${names[@]}"; do
        if [ ! -d "$prefix/Cellar/$name" ]; then
            echo "x $name: no Cellar directory, not installed?" >&2
            return 1
        fi
        echo "Cellar/$name" >>"$list"
    done
    # Links of the added formulae only: a link target carries Cellar/<name>/,
    # relative (../Cellar/eza/0.20.0/bin/eza) or absolute.
    local pattern
    pattern=$(printf 'Cellar/%s/\n' "${names[@]}")
    for d in "${link_dirs[@]}"; do
        [ -d "$prefix/$d" ] || continue
        find "$prefix/$d" -type l | while IFS= read -r link; do
            if readlink "$link" | grep -qF -f <(printf '%s\n' "$pattern"); then
                printf '%s\n' "${link#"$prefix"/}"
            fi
        done >>"$list"
    done
    # Plain tar: actions/cache compresses the file it saves, so compressing
    # here would only cost a second pass over the same bytes.
    tar -C "$prefix" -cf "$archive" -T "$list"
    echo "saved ${#names[@]} formulae and $(( $(wc -l <"$list") - ${#names[@]} )) links to $archive"
    rm -f "$list"
}

restore() {
    local archive="$1"
    [ -s "$archive" ] || { echo "x $archive missing or empty" >&2; return 1; }
    tar -C "$prefix" -xf "$archive"
    echo "restored $archive into $prefix"
}

case "${1:-}" in
    save) [ $# -eq 3 ] || usage; save "$2" "$3" ;;
    restore) [ $# -eq 2 ] || usage; restore "$2" ;;
    *) usage ;;
esac
