#!/bin/bash

# Prints a secret kept in Bitwarden, so a shell can export it without the
# secret sitting in plain text in a dotfile. Bitwarden stays the one place a
# secret is changed; the macOS login Keychain holds a copy, because asking bw
# at every new shell would ask for the master password every time.
#
#   secret.sh ITEM             the notes of the Bitwarden item named ITEM
#   secret.sh --refresh ITEM   fetch it from Bitwarden again into the copy
#                              (prints nothing; run it after changing ITEM)
#   secret.sh --forget ITEM    drop the copy
#
# A missing copy needs an unlocked vault once:
#   export BW_SESSION=$(bw unlock --raw); secret --refresh ITEM; bw lock
# Without one this fails instead of prompting, so a shell that starts with
#   API_KEY="$(secret 'api key')" && export API_KEY
# never stops to ask for a password or wait on the network; on a failure the
# variable stays unset rather than set to nothing. (`secret` is the .zshrc
# function that runs this script.)
#
# The copy trusts /usr/bin/security, so any process running as this user can
# read it without a dialog, just as it could read the exported variable. Keep
# only what every shell gets anyway in here, not a vault or signing key.
#
# The secret never goes on a command line: the copy is written through
# `security -i`, which reads its command on stdin, and read back to check it.

set -euo pipefail

# Every copy is filed under this Keychain service, so ours can be told apart.
service=dotfiles-secret
# The tests point this at a missing command to stand in for a machine without
# a Keychain; on macOS the real one is always on PATH.
security_cmd="${SECRET_SECURITY:-security}"
# security's exit status for "no such item", as opposed to a locked Keychain.
not_found=44

usage="usage: secret [--refresh | --forget] ITEM"

die() {
    echo "secret: $*" >&2
    exit 1
}

command -v "$security_cmd" >/dev/null 2>&1 ||
    die "needs the macOS Keychain; on this machine read it with: bw get notes ITEM"

# Prints the copy; fails quietly only when there is none.
cached() {
    local status=0
    "$security_cmd" find-generic-password -s "$service" -a "$1" -w 2>/dev/null || status=$?
    [ "$status" -eq 0 ] || [ "$status" -eq "$not_found" ] ||
        die "could not read the Keychain (locked? try: security unlock-keychain)"
    return "$status"
}

# Exactly the item with this name: `bw get` matches by search, so a typo could
# otherwise pick up some other item that happens to contain the word.
from_bitwarden() {
    command -v bw >/dev/null 2>&1 || die "bw is not installed (brew install bitwarden-cli)"
    command -v jq >/dev/null 2>&1 || die "jq is not installed (brew install jq)"
    [ -n "${BW_SESSION:-}" ] || die "unlock Bitwarden first: export BW_SESSION=\$(bw unlock --raw)"
    local items count
    # `bw unlock` does not sync, and list reads the local cache: without this a
    # key just changed in the web vault would be cached at its old value.
    bw sync --nointeraction >/dev/null || die "could not sync Bitwarden (see bw's message above)"
    items=$(bw list items --search "$1" --nointeraction) || die "could not read Bitwarden (see bw's message above)"
    count=$(jq --arg n "$1" '[.[] | select(.name == $n)] | length' <<<"$items")
    [ "$count" -eq 1 ] || die "Bitwarden has $count items named \"$1\"; need exactly one"
    jq -j --arg n "$1" '.[] | select(.name == $n) | .notes // ""' <<<"$items"
}

# `security -i` splits its line on quotes and reads it into a fixed buffer, and
# `-w` prints a value with any byte outside printable ASCII as hex, so only
# short printable ASCII without quotes or backslashes comes back exactly.
store() {
    local item="$1" value="$2"
    case "$item$value" in
        *'"'* | *"'"* | *\\* | *$'\n'*) die "\"$item\" has a quote, backslash or line break; not cached" ;;
    esac
    [ "${#value}" -le 1000 ] && [ "${#item}" -le 200 ] || die "\"$item\" is too long to cache"
    if printf '%s' "$item$value" | LC_ALL=C grep -q '[^ -~]'; then
        die "\"$item\" has a character outside printable ASCII; not cached"
    fi
    printf 'add-generic-password -U -s "%s" -a "%s" -T /usr/bin/security -w "%s"\n' \
        "$service" "$item" "$value" | "$security_cmd" -i >/dev/null 2>&1 || true
    [ "$(cached "$item" 2>/dev/null || true)" = "$value" ] || die "could not save \"$item\" to the Keychain"
}

# Says only that it is done: run by hand in a terminal, printing the secret
# would put it on screen and in the scrollback. The copy is overwritten in
# place (-U), so a locked vault keeps the old one.
refresh() {
    local value
    value=$(from_bitwarden "$1")
    [ -n "$value" ] || die "Bitwarden item \"$1\" has empty notes"
    store "$1" "$value"
    echo "cached: $1" >&2
}

forget() {
    local status=0
    "$security_cmd" delete-generic-password -s "$service" -a "$1" >/dev/null 2>&1 || status=$?
    [ "$status" -eq 0 ] || [ "$status" -eq "$not_found" ] ||
        die "could not delete \"$1\" from the Keychain (locked? try: security unlock-keychain)"
}

# Never fetches: a shell starting up must not wait on Bitwarden.
show() {
    local value status=0
    value=$(cached "$1") || status=$?
    if [ "$status" -eq 0 ] && [ -n "$value" ]; then
        printf '%s\n' "$value"
    elif [ "$status" -eq 0 ] || [ "$status" -eq "$not_found" ]; then
        die "\"$1\" is not in the Keychain yet; run: secret --refresh $(printf '%q' "$1") (needs BW_SESSION)"
    else
        exit 1
    fi
}

case "${1:-}" in
    --refresh | --forget)
        [ $# -eq 2 ] && [ -n "$2" ] || die "$usage"
        if [ "$1" = --refresh ]; then
            refresh "$2"
        else
            forget "$2"
        fi
        ;;
    "" | -*)
        die "$usage"
        ;;
    *)
        [ $# -eq 1 ] || die "$usage"
        show "$1"
        ;;
esac
