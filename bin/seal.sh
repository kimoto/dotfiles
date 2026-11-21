#!/bin/bash

# Seals a file or folder into one age-encrypted tar, for what must not be read
# if it leaks or syncs somewhere by mistake (backups.md: encrypt before it
# leaves the machine). The archive is decrypted again and hashed against the
# tar that went in before anything is reported as sealed, so a sealed file is
# known to open.
#
#   seal.sh PATH            -> PATH.tar.age beside PATH; PATH is left alone
#   seal.sh --remove PATH   -> the same, then PATH is deleted once it checks out
#   seal.sh --open FILE.tar.age [DIR]   -> unpacks into DIR (default: beside FILE)
#
# --remove uses rm, not the Trash: the Trash would keep the very plaintext
# this is meant to get rid of.
#
# Sealing needs only the public key. The check and --open need the secret one,
# which can stay in a password manager and reach age on stdin, never a file:
#   SEAL_RECIPIENT      the age1... public key, or else
#   SEAL_RECIPIENTS     a file of them (default ~/.local/share/age/recipients.txt)
#   SEAL_IDENTITY_CMD   a command printing the secret key (e.g. bw get notes ITEM)
#   SEAL_IDENTITY       or a key file (default ~/.local/share/age/key.txt)
# Both stay outside ~/.config, which is this repo's config/: a key there would
# sit in a git working tree.

set -euo pipefail

identity="${SEAL_IDENTITY:-$HOME/.local/share/age/key.txt}"
recipients="${SEAL_RECIPIENTS:-$HOME/.local/share/age/recipients.txt}"

die() {
    echo "seal: $*" >&2
    exit 1
}

need_identity() {
    [ -n "${SEAL_IDENTITY_CMD:-}" ] || [ -r "$identity" ] ||
        die "no secret key: set SEAL_IDENTITY_CMD, or make $identity with age-keygen -o"
}

# age -d FILE with the secret key; from SEAL_IDENTITY_CMD it arrives on stdin.
decrypt() {
    if [ -n "${SEAL_IDENTITY_CMD:-}" ]; then
        bash -c "$SEAL_IDENTITY_CMD" | age -d -i - "$1"
    else
        age -d -i "$identity" "$1"
    fi
}

# Prints the two words age takes to name the public key.
recipient_args() {
    if [ -n "${SEAL_RECIPIENT:-}" ]; then
        printf '%s\n%s\n' -r "$SEAL_RECIPIENT"
    elif [ -s "$recipients" ]; then
        printf '%s\n%s\n' -R "$recipients"
    else
        local pub
        if [ -n "${SEAL_IDENTITY_CMD:-}" ]; then
            pub=$(bash -c "$SEAL_IDENTITY_CMD" | age-keygen -y) || return 1
        else
            pub=$(age-keygen -y "$identity") || return 1
        fi
        [ -n "$pub" ] || return 1
        printf '%s\n%s\n' -r "$pub"
    fi
}

# Every file below PATH with its size and mtime, to tell whether anything was
# written there while it was being sealed. perl, because BSD and GNU find and
# stat print these apart.
snapshot() {
    perl -MFile::Find -e '
        find({ no_chdir => 1, wanted => sub {
            my @s = lstat($_) or return;
            print "$File::Find::name\t$s[7]\t$s[9]\n";
        }}, $ARGV[0]);
    ' "$1" | sort
}

# GNU tar counts a file already there as an error under -k; bsdtar skips it.
keep_old_flag() {
    if tar --version 2>/dev/null | grep -q 'GNU tar'; then
        echo --skip-old-files
    else
        echo -k
    fi
}

# sha256sum on Linux, shasum on macOS; an empty hash never matches below.
hash_stream() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | cut -d' ' -f1
    else
        shasum -a 256 | cut -d' ' -f1
    fi
}

# A file already there is kept, never replaced by the sealed copy's older
# version.
open_sealed() {
    local file="$1" dir="${2:-}"
    [ -f "$file" ] || die "no file $file"
    [ -n "$dir" ] || dir=$(dirname -- "$file")
    need_identity
    mkdir -p -- "$dir"
    decrypt "$file" | tar -x "$(keep_old_flag)" -f - -C "$dir"
    echo "opened: $file -> $dir"
}

seal() {
    local path="$1" remove="$2" abs parent base out fifo hash_in hash_back rargs rflag rvalue
    path="${path%/}"
    # A link would be sealed as a link and rm would drop only the link,
    # leaving the plaintext it points to.
    [ ! -L "$path" ] || die "$path is a symlink; seal what it points to"
    [ -e "$path" ] || die "no file or folder $path"
    # Absolute and resolved, so "." or ".." names the folder itself and the
    # sealed file lands beside it, not inside the tree being read.
    if [ -d "$path" ]; then
        abs=$(cd -- "$path" && pwd -P)
    else
        abs="$(cd -- "$(dirname -- "$path")" && pwd -P)/$(basename -- "$path")"
    fi
    parent="${abs%/*}"
    parent="${parent:-/}"
    base="${abs##*/}"
    [ -n "$base" ] || die "will not seal /"
    out="$parent/$base.tar.age"
    [ ! -e "$out" ] || die "$out already exists"
    need_identity
    rargs=$(recipient_args) || die "no public key: set SEAL_RECIPIENT or write it to $recipients"
    rflag=${rargs%%$'\n'*}
    rvalue=${rargs#*$'\n'}

    # Globals, not locals: the EXIT trap runs after this function has
    # returned, and an interrupted run must not leave a half-written file.
    tmp=$(mktemp -d)
    part="$out.part"
    trap 'rm -rf "$tmp" "$part"' EXIT
    # One tar stream, hashed on its way into age: a second tar of the same
    # folder is not promised to come out byte for byte the same. "./" keeps a
    # name that starts with "-" from being read as an option.
    fifo="$tmp/tar"
    mkfifo "$fifo"
    snapshot "$abs" >"$tmp/before"
    hash_stream <"$fifo" >"$tmp/in" &
    if ! tar -cf - -C "$parent" "./$base" | tee "$fifo" | age "$rflag" "$rvalue" -o "$part"; then
        wait || true
        die "could not seal $abs"
    fi
    wait
    hash_in=$(cat "$tmp/in")
    hash_back=$(decrypt "$part" | hash_stream) || hash_back=""
    if [ -z "$hash_in" ] || [ "$hash_in" != "$hash_back" ]; then
        die "the sealed copy did not decrypt to what went in; $abs is untouched"
    fi
    mv "$part" "$out"
    path="$abs"
    echo "sealed: $path -> $out (tar sha256 $hash_in)"
    if [ "$remove" = 1 ]; then
        # The archive is on disk before its plaintext goes.
        sync
        if ! snapshot "$abs" | cmp -s - "$tmp/before"; then
            die "$abs changed while it was sealed; kept it (the sealed copy is $out)"
        fi
        rm -rf -- "$path"
        echo "removed: $path"
    fi
}

command -v age >/dev/null 2>&1 || die "age is not installed (brew install age)"

case "${1:-}" in
    --open)
        shift
        [ $# -ge 1 ] && [ $# -le 2 ] || die "usage: seal.sh --open FILE.tar.age [DIR]"
        open_sealed "$@"
        ;;
    --remove)
        shift
        [ $# -eq 1 ] || die "usage: seal.sh --remove PATH"
        seal "$1" 1
        ;;
    -h | --help)
        sed -n '3,23p' "$0" | sed 's/^# \{0,1\}//'
        ;;
    "")
        die "usage: seal.sh [--remove] PATH | --open FILE.tar.age [DIR]"
        ;;
    *)
        [ $# -eq 1 ] || die "usage: seal.sh [--remove] PATH"
        seal "$1" 0
        ;;
esac
