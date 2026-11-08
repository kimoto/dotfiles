#!/bin/bash
# Pack or unpack the formulae one CI run installed into the Homebrew prefix,
# so a later run on the same image restores them instead of installing again.
#
#   ci/brew_cellar_cache.sh save <archive> <added-list>
#   ci/brew_cellar_cache.sh restore <archive>
#
# <added-list> names one formula per line: the ones this run installed, i.e.
# the diff of `brew list --formula` before and after. For each, the archive
# takes its Cellar directory (the install receipt lives there, which is what
# makes brew count it as installed) and every symlink in the prefix's link
# directories that points into it, so a restore needs no `brew link`.
# Restore skips every formula this runner already has installed.
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
# One "path<TAB>formula" line per archived path.
manifest=.cellar-manifest

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
        printf 'Cellar/%s\t%s\n' "$name" "$name" >>"$list"
    done
    # Links of the added formulae only: a link target carries Cellar/<name>/,
    # relative (../Cellar/eza/0.20.0/bin/eza) or absolute. One perl process
    # over all links, not a readlink per link: a prefix holds ~10,000 of them,
    # and a fork each took over two minutes on the macOS runner.
    local dirs=()
    for d in "${link_dirs[@]}"; do
        [ -d "$prefix/$d" ] && dirs+=("$prefix/$d")
    done
    if [ "${#dirs[@]}" -gt 0 ]; then
        find "${dirs[@]}" -type l -print0 \
            | perl -0 -ne 'BEGIN { %n = map { $_ => 1 } @ARGV; @ARGV = () }
                           chomp; my $t = readlink($_) // next;
                           print "$_\t$1\n" if $t =~ m{Cellar/([^/]+)/} && $n{$1}' "${names[@]}" \
            | sed "s|^$prefix/||" >>"$list"
    fi
    # Only what still exists: a link that vanished since the listing would
    # stop tar, and losing one link is cheaper than losing the whole archive.
    local kept p name
    kept=$(mktemp)
    while IFS=$'\t' read -r p name; do
        [ -e "$prefix/$p" ] || [ -L "$prefix/$p" ] || { echo "skipping vanished $p" >&2; continue; }
        printf '%s\t%s\n' "$p" "$name"
    done <"$list" >"$kept"
    # The manifest travels inside the archive, so restore knows which formula
    # each path belongs to without a second cache entry.
    mv -f "$kept" "$prefix/$manifest"
    cut -f1 "$prefix/$manifest" >"$list"
    echo "$manifest" >>"$list"
    # Plain tar: actions/cache compresses the file it saves, so compressing
    # here would only cost a second pass over the same bytes.
    tar -C "$prefix" -cf "$archive" -T "$list"
    echo "saved ${#names[@]} formulae and $(( $(wc -l <"$list") - 1 - ${#names[@]} )) links to $archive"
    rm -f "$list" "$prefix/$manifest"
}

# Runners of one image do not all ship the same formulae. A formula the
# archive holds may already be installed here, sometimes linked through a
# whole-directory symlink that tar refuses to extract through, so restore
# skips every path of such a formula and leaves the runner's own copy.
restore() {
    local archive="$1"
    [ -s "$archive" ] || { echo "x $archive missing or empty" >&2; return 1; }
    local list skipped
    list=$(mktemp)
    skipped=$(mktemp)
    tar -xOf "$archive" "$manifest" | while IFS=$'\t' read -r p name; do
        if [ -d "$prefix/Cellar/$name" ]; then
            echo "$name" >>"$skipped"
        else
            printf '%s\n' "$p"
        fi
    done >"$list"
    if [ -s "$skipped" ]; then
        echo "already installed here, not restored: $(sort -u "$skipped" | tr '\n' ' ')"
    fi
    if [ -s "$list" ]; then
        tar -C "$prefix" -xf "$archive" -T "$list"
    fi
    echo "restored $(wc -l <"$list" | tr -d ' ') paths from $archive into $prefix"
    rm -f "$list" "$skipped"
}

case "${1:-}" in
    save) [ $# -eq 3 ] || usage; save "$2" "$3" ;;
    restore) [ $# -eq 2 ] || usage; restore "$2" ;;
    *) usage ;;
esac
