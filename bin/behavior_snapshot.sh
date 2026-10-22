#!/bin/bash

# Print the state a checkout's shell config leaves behind, so a refactor can
# show it changed nothing: snapshot before, snapshot after, and an empty diff
# is the evidence. Tests only see what they assert; the snapshot sees every
# option, alias, key, zstyle, function and variable at once.
#
# Usage:
#   behavior_snapshot.sh zsh  [CHECKOUT]   state after .zshrc loads
#   behavior_snapshot.sh tmux [CHECKOUT]   state after .tmux.conf loads
#   behavior_snapshot.sh compare [BASE]    both, BASE (default origin/main)
#                                          against this working tree; exit 1
#                                          and print the diff if they differ
# CHECKOUT defaults to the checkout this script lives in.
#
# Each load runs under a throwaway HOME whose .zshrc, .tmux.conf, .config and
# bin point at CHECKOUT, the way mklink.sh lays out a real one. With the real
# HOME, both sides of a compare would read the same ~/.config — the main
# checkout's — and a change under config/ would never show; ~/.zshrc.local and
# ~/.tmux.conf.local would leak one machine's state in, and the completion dump
# and zcompile output left by an earlier shell would decide part of the result.
#
# ⚠️ No plugins load, on either side: sheldon is shadowed by a stub that fails,
# and tpm is not in that HOME. Installing them there would mean a network fetch
# per snapshot. So the snapshot covers what .zshrc and .tmux.conf define, not
# config/sheldon/plugins.toml or the files only it sources (config/zsh/*.zsh).
#
# Paths are rewritten to <HOME> and <REPO>, and values that move on every run
# (time, PIDs, random numbers, the tty) are dropped, so two loads of the same
# config print the same bytes.

set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)

usage() {
    echo "usage: behavior_snapshot.sh zsh|tmux [CHECKOUT] | compare [BASE]" >&2
    exit 2
}

# make_home <checkout>: a fresh HOME that sees <checkout> as the dotfiles.
make_home() {
    local home
    home=$(mktemp -d)
    ln -s "$1/.zshrc" "$home/.zshrc"
    ln -s "$1/config" "$home/.config"
    ln -s "$1/bin" "$home/bin"
    ln -s "$1/.tmux.conf" "$home/.tmux.conf"
    # ~/.local/bin: first on the PATH zsh starts with, and .zshrc keeps it
    # ahead of Homebrew's sheldon.
    mkdir -p "$home/.local/bin"
    printf '#!/bin/sh\nexit 1\n' >"$home/.local/bin/sheldon"
    chmod +x "$home/.local/bin/sheldon"
    printf '%s\n' "$home"
}

# normalize <home> <checkout>: rewrite both paths so two checkouts compare.
# Longest first: mktemp may hand out a HOME under the checkout, or the reverse.
normalize() {
    local first="$1" first_tag="<HOME>" second="$2" second_tag="<REPO>"
    if [ "${#second}" -gt "${#first}" ]; then
        first="$2" first_tag="<REPO>" second="$1" second_tag="<HOME>"
    fi
    FIRST="$first" FIRST_TAG="$first_tag" SECOND="$second" SECOND_TAG="$second_tag" \
        perl -pe 's/\Q$ENV{FIRST}\E/$ENV{FIRST_TAG}/g; s/\Q$ENV{SECOND}\E/$ENV{SECOND_TAG}/g'
}

# Run inside the loaded shell. zsh lists options, aliases, keymaps, zstyles,
# functions and parameters sorted by name already, so the order is stable.
# Left out of the parameters: what zsh itself moves between runs (clock, PIDs,
# random, tty, history counters) and the probe's own text and call stack.
# shellcheck disable=SC2016  # zsh code, expanded by zsh
ZSH_PROBE='
print -r -- "== setopt"; setopt
print -r -- "== alias"; alias -L
print -r -- "== bindkey"
for _km in $(bindkey -l); do print -r -- "-- $_km"; bindkey -L -M $_km; done
print -r -- "== zle"; zle -lL
print -r -- "== zstyle"; zstyle -L
print -r -- "== functions"; functions
print -r -- "== parameters"
_volatile=(EPOCHREALTIME EPOCHSECONDS epochtime SECONDS RANDOM SRANDOM LINENO
  PPID TTY TTYIDLE HISTCMD _ argv funcstack funcfiletrace funcsourcetrace
  functrace zsh_eval_context ZSH_EXECUTION_STRING _km _p _volatile)
for _p in ${(ok)parameters}; do
  (( ${_volatile[(Ie)$_p]} )) && continue
  typeset -p -- $_p 2>/dev/null
done
'

snapshot_zsh() {
    local checkout="$1" home rc=0
    home=$(make_home "$checkout")
    # From HOME, so $PWD does not depend on where the caller stood. CI is
    # cleared so .zshrc does not turn on err_exit; the startup reminders are
    # off because they touch the network and print per-machine noise.
    # shellcheck disable=SC2016  # expanded by the inner sh
    env -i HOME="$home" PATH="$home/.local/bin:$PATH" TERM=xterm-256color \
        LANG="${LANG:-C.UTF-8}" DOTFILES_NO_SYNC_CHECK=1 DOTFILES_NO_BREW_CHECK=1 \
        DOTFILES_NO_MISE_CHECK=1 \
        sh -c 'cd "$HOME" && exec zsh -ic "$1"' sh "$ZSH_PROBE" </dev/null 2>&1 |
        normalize "$home" "$checkout" || rc=$?
    rm -rf "$home"
    return "$rc"
}

snapshot_tmux() {
    local checkout="$1" home sock rc=0
    home=$(make_home "$checkout")
    sock="behavior_snapshot_$$_${RANDOM}"
    {
        env -i HOME="$home" PATH="$PATH" TERM=xterm-256color \
            tmux -L "$sock" -f /dev/null new-session -d -x 200 -y 50 -c "$home"
        echo "== source-file"
        env -i HOME="$home" PATH="$PATH" tmux -L "$sock" source-file "$checkout/.tmux.conf" 2>&1 || true
        echo "== server"; tmux -L "$sock" show -s
        echo "== session"; tmux -L "$sock" show -g
        echo "== window"; tmux -L "$sock" show -gw
        echo "== keys"; tmux -L "$sock" list-keys
    } | normalize "$home" "$checkout" || rc=$?
    tmux -L "$sock" kill-server 2>/dev/null || true
    rm -rf "$home"
    return "$rc"
}

compare() {
    local base="$1" kind status=0
    # Global: the EXIT trap reads it after compare has returned.
    work=$(mktemp -d)
    trap 'git -C "$BASE_DIR" worktree remove --force "$work/base" >/dev/null 2>&1; rm -rf "$work"' EXIT
    git -C "$BASE_DIR" worktree add --quiet --detach "$work/base" "$base"
    for kind in zsh tmux; do
        "snapshot_$kind" "$work/base" >"$work/$kind.before"
        "snapshot_$kind" "$BASE_DIR" >"$work/$kind.after"
        if diff -u --label "$kind@$base" --label "$kind@worktree" \
            "$work/$kind.before" "$work/$kind.after"; then
            echo "$kind: no difference from $base"
        else
            status=1
        fi
    done
    return "$status"
}

case "${1:-}" in
    zsh | tmux)
        checkout=$(cd "${2:-$BASE_DIR}" && pwd)
        "snapshot_$1" "$checkout"
        ;;
    compare) compare "${2:-origin/main}" ;;
    *) usage ;;
esac
