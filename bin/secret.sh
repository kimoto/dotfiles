#!/bin/bash

# Prints a secret kept in Bitwarden, so a shell can export it without the
# secret sitting in plain text in a dotfile. Bitwarden stays the one place a
# secret is changed; the macOS login Keychain holds a copy, because asking bw
# at every new shell would ask for the master password every time.
#
#   secret.sh ITEM             the Bitwarden item named ITEM: its password,
#                              or its notes when it has none
#   secret.sh --refresh ITEM   fetch it from Bitwarden again into the copy
#                              (prints nothing; run it after changing ITEM)
#   secret.sh --forget ITEM    drop the copy
#   secret.sh --set ITEM [-]   put a new value into Bitwarden and the copy:
#                              the clipboard (then cleared), or stdin with -
#
# --set is how a key is replaced: make the new key on the provider's page,
# press its copy button, run `secret --set ITEM`, then revoke the old key. The
# value is never shown, and it is read back from Bitwarden before it is cached.
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

usage="usage: secret [--refresh | --forget] ITEM | --set ITEM [-]"
# The tests point these at stubs; on macOS they are the system clipboard.
paste_cmd="${SECRET_PASTE:-pbpaste}"
copy_cmd="${SECRET_COPY:-pbcopy}"

# Set once --set has written Bitwarden, so a later failure says where the new
# value already is instead of leaving the two silently apart.
written=""

die() {
    echo "secret: $*" >&2
    [ -z "$written" ] ||
        echo "secret: Bitwarden already holds the new \"$written\";" \
            "once fixed, run: secret --refresh $(printf '%q' "$written")" >&2
    exit 1
}

command -v "$security_cmd" >/dev/null 2>&1 ||
    die "needs the macOS Keychain; on this machine read it with: bw get password ITEM (or notes)"

# Prints the copy; fails quietly only when there is none.
cached() {
    local status=0
    "$security_cmd" find-generic-password -s "$service" -a "$1" -w 2>/dev/null || status=$?
    [ "$status" -eq 0 ] || [ "$status" -eq "$not_found" ] ||
        die "could not read the Keychain (locked? try: security unlock-keychain)"
    return "$status"
}

bw_ready() {
    command -v bw >/dev/null 2>&1 || die "bw is not installed (brew install bitwarden-cli)"
    command -v jq >/dev/null 2>&1 || die "jq is not installed (brew install jq)"
    [ -n "${BW_SESSION:-}" ] || die "unlock Bitwarden first: export BW_SESSION=\$(bw unlock --raw)"
    # `bw unlock` does not sync, and list reads the local cache: without this a
    # key just changed in the web vault would be cached at its old value.
    bw sync --nointeraction >/dev/null || die "could not sync Bitwarden (see bw's message above)"
}

# The items named exactly ITEM, as a JSON array: `bw get` matches by search, so
# a typo could otherwise pick up some other item that happens to contain the word.
named_items() {
    local items
    items=$(bw list items --search "$1" --nointeraction) || die "could not read Bitwarden (see bw's message above)"
    jq --arg n "$1" '[.[] | select(.name == $n)]' <<<"$items"
}

# The same rule homeprobe-secrets reads an item by: the password field or the
# notes, never both, so one item can serve both tools. ITEMS is named_items'.
one_field() {
    if ! jq -e '.[0] | (.login.password // "") == "" or (.notes // "") == ""' <<<"$2" >/dev/null; then
        die "Bitwarden item \"$1\" has both a password and notes; keep only one"
    fi
}

from_bitwarden() {
    local items count
    bw_ready
    items=$(named_items "$1")
    count=$(jq length <<<"$items")
    [ "$count" -eq 1 ] || die "Bitwarden has $count items named \"$1\"; need exactly one"
    one_field "$1" "$items"
    jq -j '.[0] | if (.login.password // "") != "" then .login.password else .notes // "" end' <<<"$items"
}

# `security -i` splits its line on quotes and reads it into a fixed buffer, and
# `-w` prints a value with any byte outside printable ASCII as hex, so only
# short printable ASCII without quotes or backslashes comes back exactly.
cacheable() {
    local item="$1" value="$2"
    case "$item$value" in
        *'"'* | *"'"* | *\\* | *$'\n'*) die "\"$item\" has a quote, backslash or line break; not cached" ;;
    esac
    [ "${#value}" -le 1000 ] && [ "${#item}" -le 200 ] || die "\"$item\" is too long to cache"
    if printf '%s' "$item$value" | LC_ALL=C grep -q '[^ -~]'; then
        die "\"$item\" has a character outside printable ASCII; not cached"
    fi
}

store() {
    local item="$1" value="$2"
    cacheable "$item" "$value"
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
    [ -n "$value" ] || die "Bitwarden item \"$1\" has neither a password nor notes"
    store "$1" "$value"
    echo "cached: $1" >&2
}

# The new value reaches jq and bw through a pipe, never argv. Only an item with
# exactly this name is touched, and only the field that holds its value (the
# password if it has one, else the notes); with none, a secure note is made.
# A value the Keychain could not carry, or a Keychain that cannot be read, is
# refused before Bitwarden is written.
set_value() {
    local item="$1" from="$2" value items count id
    if [ "$from" = - ]; then
        # Typed at the terminal, cat would echo the key onto the screen.
        [ ! -t 0 ] || die "pipe the value in; - does not read from the terminal"
        value=$(cat)
    else
        command -v "$paste_cmd" >/dev/null 2>&1 || die "no clipboard here; pipe the value in: secret --set ITEM -"
        value=$("$paste_cmd") || die "could not read the clipboard"
    fi
    # A copy button or a terminal paste may bring a newline or spaces along.
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    [ -n "$value" ] || die "the new value is empty; copy the key first"
    cacheable "$item" "$value"
    cached "$item" >/dev/null || true
    bw_ready
    items=$(named_items "$item")
    count=$(jq length <<<"$items")
    case "$count" in
        0)
            bw get template item --nointeraction |
                jq --arg n "$item" --rawfile v <(printf '%s' "$value") \
                    '.type = 2 | .secureNote = {type: 0} | .login = null | .name = $n | .notes = $v' |
                bw encode | bw create item --nointeraction >/dev/null ||
                die "could not create \"$item\" in Bitwarden (see bw's message above)"
            ;;
        1)
            # Which field to replace would be a guess, and the other may be a
            # password nobody else has a copy of.
            one_field "$item" "$items"
            id=$(jq -r '.[0].id' <<<"$items")
            bw get item "$id" --nointeraction |
                jq --rawfile v <(printf '%s' "$value") \
                    'if (.login.password // "") != "" then .login.password = $v else .notes = $v end' |
                bw encode | bw edit item "$id" --nointeraction >/dev/null ||
                die "could not update \"$item\" in Bitwarden (see bw's message above)"
            ;;
        *) die "Bitwarden has $count items named \"$item\"; need exactly one" ;;
    esac
    written="$item"
    # Bitwarden has it now, so the clipboard need not keep it, even if a step
    # below fails.
    if [ "$from" != - ]; then
        printf '' | "$copy_cmd" || echo "secret: could not clear the clipboard; copy something else over it" >&2
    fi
    # Read back, not trusted: what is cached is what Bitwarden now holds.
    [ "$(from_bitwarden "$item")" = "$value" ] || die "Bitwarden did not keep the new value of \"$item\""
    store "$item" "$value"
    echo "stored: $item (Bitwarden and the Keychain); now revoke the old key" >&2
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
    --set)
        [ $# -eq 2 ] || { [ $# -eq 3 ] && [ "$3" = - ]; } || die "$usage"
        [ -n "$2" ] || die "$usage"
        set_value "$2" "${3:-clipboard}"
        ;;
    "" | -*)
        die "$usage"
        ;;
    *)
        [ $# -eq 1 ] || die "$usage"
        show "$1"
        ;;
esac
