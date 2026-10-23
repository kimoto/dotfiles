#!/bin/bash

# Print one Markdown table row with how long the things a person waits on take,
# for the "Speed watch log" issue. Columns, in the issue's order:
#
#   date (JST) | commit | zsh | nvim | tmux | hook | pre-commit | bats | rules
#
# Times are the median of SPEED_REPORT_RUNS runs (default 10), in ms. `n/a`
# means the tool was missing, never that it was fast; `fail` means the command
# under test exited non-zero. rules is bytes, not time.
#
# Usage:
#   speed_report.sh            the whole row
#   speed_report.sh ITEM...    just those values, one per line (zsh, nvim,
#                              tmux, hook, precommit, bats, rules)
#   SPEED_REPORT_VERBOSE=1     also every hook's median on stderr, so the
#                              slowest one can be named
#
# Everything runs under one HOME kept between runs (SPEED_REPORT_HOME, default
# ~/.cache/speed_report/home) whose dotfiles point at this checkout, the way
# mklink.sh lays out a real one. The real HOME would measure whatever that
# machine's ~/.zshrc.local adds, and a fresh HOME per run would put plugin
# clones inside the timing. Plugins are installed there before measuring, so
# the first run needs the network.
#
# Each measurement starts with one untimed run: it fills the completion dump,
# the evalcache files and the page cache, which a person's second shell of the
# day also finds full.

set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
RUNS="${SPEED_REPORT_RUNS:-10}"
# One run: the suite takes over a minute, so ten would cost a quarter of an
# hour, and its run-to-run spread is a few percent, well inside the 1.25x a
# regression has to cross.
BATS_RUNS="${SPEED_REPORT_BATS_RUNS:-1}"
# A script that its .bats file and shellcheck both cover, so the commit runs
# the hooks a typical bin/ change does. Fixed, or the number would move with
# whichever file was picked.
COMMIT_FILE="${SPEED_REPORT_COMMIT_FILE:-bin/keys.sh}"

# median: the middle of the numbers on stdin (the lower middle for an even
# count, so the value is always one that was measured). Any non-number wins:
# one failed run makes the whole item `fail`, not a faster median.
median() {
    awk '
        $0 !~ /^[0-9]+$/ { bad = $0; next }
        { v[++n] = $0 }
        END {
            if (bad != "") { print bad; exit }
            if (n == 0) { print "n/a"; exit }
            # sort -n would be a second process per item; n is ten.
            for (i = 2; i <= n; i++) {
                x = v[i]
                for (j = i - 1; j >= 1 && v[j] > x; j--) v[j + 1] = v[j]
                v[j + 1] = x
            }
            print v[int((n + 1) / 2)]
        }'
}

# Sourced by test/speed_report.bats to unit-test median.
[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

# clock_us: microseconds. bash 5's EPOCHREALTIME costs no process; macOS's
# bash 3.2 lacks it and its date has no %N, so perl there.
clock_us() {
    if [ -n "${EPOCHREALTIME:-}" ]; then
        printf '%s\n' "${EPOCHREALTIME//[.,]/}"
    else
        perl -MTime::HiRes=time -e 'printf "%d\n", time * 1e6'
    fi
}

# ms CMD...: wall time of CMD in ms, or `fail`. CMD may be a function; its
# output is dropped so only the number reaches stdout.
ms() {
    local t0 t1 rc=0
    t0=$(clock_us)
    "$@" >/dev/null 2>&1 </dev/null || rc=$?
    t1=$(clock_us)
    if [ "$rc" -eq 0 ]; then echo $(((t1 - t0) / 1000)); else echo fail; fi
}

# repeat N CMD...: one warm-up, then the median of N timed runs.
repeat() {
    local n=$1 i
    shift
    "$@" >/dev/null 2>&1 </dev/null || true
    for ((i = 0; i < n; i++)); do
        ms "$@"
    done | median
}

have() { command -v "$1" >/dev/null 2>&1; }

# mise's shims look for their config under HOME; pin it to the real one before
# HOME moves, or every shimmed tool fails inside the measured HOME.
pin_mise_dirs() {
    : "${MISE_DATA_DIR:=${XDG_DATA_HOME:-$HOME/.local/share}/mise}"
    : "${MISE_CONFIG_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/mise}"
    : "${MISE_STATE_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/mise}"
    : "${MISE_CACHE_DIR:=${XDG_CACHE_HOME:-$HOME/.cache}/mise}"
    export MISE_DATA_DIR MISE_CONFIG_DIR MISE_STATE_DIR MISE_CACHE_DIR
}

prepare_home() {
    local f
    MEASURE_HOME="${SPEED_REPORT_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/speed_report/home}"
    mkdir -p "$MEASURE_HOME/.local/bin" "$MEASURE_HOME/tmp" "$MEASURE_HOME/.vim/undo"
    for f in .zshrc .zshenv .zprofile .tmux.conf .vimrc .bashrc .inputrc; do
        [ -e "$BASE_DIR/$f" ] && ln -sfn "$BASE_DIR/$f" "$MEASURE_HOME/$f"
    done
    ln -sfn "$BASE_DIR/config" "$MEASURE_HOME/.config"
    ln -sfn "$BASE_DIR/bin" "$MEASURE_HOME/bin"
    pin_mise_dirs
    # The real XDG dirs would send plugin clones and caches outside it.
    unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME
    export TERM=xterm-256color
    unset TMUX TMUX_PANE CLAUDE_CODE_REMOTE
}

in_home() { HOME="$MEASURE_HOME" "$@"; }

measure_zsh() {
    have zsh || { echo n/a; return; }
    if have sheldon; then in_home sheldon lock >/dev/null 2>&1 || true; fi
    # Same toggles as ci/zsh_bench.sh: the sync, brew and mise reminders are
    # network and noise, not startup. CI= because CI=true makes .zshrc strict.
    # Set here only: exported for the whole script, they would also switch
    # off the scripts the bats suite tests.
    repeat "$RUNS" env HOME="$MEASURE_HOME" CI= DOTFILES_NO_SYNC_CHECK=1 \
        DOTFILES_NO_BREW_CHECK=1 DOTFILES_NO_MISE_CHECK=1 zsh -lic exit
}

measure_nvim() {
    have nvim || { echo n/a; return; }
    # The first start clones every vim.pack plugin; it is the warm-up's job,
    # but a clone can outlast it, so wait for it here.
    in_home nvim --headless +qa >/dev/null 2>&1 </dev/null || true
    repeat "$RUNS" env HOME="$MEASURE_HOME" nvim --headless +qa
}

# A new server reading the config with -f, as a terminal starting tmux does.
# tpm's `run` blocks until every plugin is loaded, so new-session returns
# after the plugins too.
tmux_start() {
    HOME="$MEASURE_HOME" tmux -L speed_report -f "$MEASURE_HOME/.tmux.conf" \
        new-session -d -x 200 -y 50 || return 1
    HOME="$MEASURE_HOME" tmux -L speed_report kill-server
}

measure_tmux() {
    have tmux || { echo n/a; return; }
    in_home "$BASE_DIR/bin/install_tmux_plugins.sh" >/dev/null 2>&1 || true
    repeat "$RUNS" tmux_start
}

# hook_payload EVENT MATCHER: what Claude Code would send, enough for each
# hook to do its real work: a Bash call that is a commit, so the secret scan
# runs, and a transcript, so the context check reads one.
hook_payload() {
    local tool=Bash
    case "$2" in "" | null | *Bash*) ;; *) tool=${2%%|*} ;; esac
    jq -cn --arg ev "$1" --arg tool "$tool" --arg cwd "$BASE_DIR" \
        --arg tr "$MEASURE_HOME/transcript.jsonl" '
        {session_id: "speed-report", transcript_path: $tr, cwd: $cwd,
         hook_event_name: $ev, source: "startup", prompt: "hi",
         tool_name: $tool, tool_input: {command: "git commit -m x"},
         tool_response: {stdout: ""}}'
}

hook_run() { printf '%s' "$1" | sh -c "$2" >/dev/null 2>&1; }

# The slowest hook, per call: the repo's own .claude/settings.json and what
# bin/install_*_hooks.sh registers. A hook runs on every tool call it matches,
# so its cost is per call, not per session.
measure_hook() {
    local settings="$MEASURE_HOME/.claude/settings.json" installer line ev matcher cmd t
    have jq || { echo n/a; return; }
    mkdir -p "$MEASURE_HOME/.claude"
    echo '{}' >"$settings"
    for installer in "$BASE_DIR"/bin/install_claude_*hook*.sh; do
        in_home "$installer" >/dev/null 2>&1 || true
    done
    jq -cn '{type: "assistant", message: {usage:
        {input_tokens: 1000, cache_read_input_tokens: 50000, output_tokens: 10}}}' \
        >"$MEASURE_HOME/transcript.jsonl"
    jq -r '.hooks // {} | to_entries[] | .key as $ev | .value[]
           | (.matcher // "") as $m | .hooks[] | [$ev, $m, .command] | join("\u001f")' \
        "$settings" "$BASE_DIR/.claude/settings.json" |
        # \037, not a tab: read merges runs of whitespace separators, so an
        # empty matcher would shift the command into its place.
        while IFS=$'\037' read -r ev matcher cmd; do
            line=$(hook_payload "$ev" "$matcher")
            t=$(HOME="$MEASURE_HOME" CLAUDE_PROJECT_DIR="$BASE_DIR" \
                repeat "$RUNS" hook_run "$line" "$cmd")
            [ -n "${SPEED_REPORT_VERBOSE:-}" ] && printf '%6s  %s  %s\n' "$t" "$ev" "$cmd" >&2
            echo "$t"
        done | awk '
            $0 !~ /^[0-9]+$/ { bad = $0; next }
            $0 > max { max = $0 }
            END { print bad != "" ? bad : (NR ? max : "n/a") }'
}

# One commit that changes COMMIT_FILE, in a throwaway worktree of HEAD, so
# the checkout under test is never touched.
precommit_once() {
    printf '# speed report\n' >>"$1/$COMMIT_FILE"
    git -C "$1" add "$COMMIT_FILE"
    (cd "$1" && lefthook run pre-commit >/dev/null 2>&1)
    local rc=$?
    git -C "$1" reset -q --hard
    return "$rc"
}

measure_precommit() {
    local wt rc=0
    have lefthook || { echo n/a; return; }
    wt=$(mktemp -d)
    git -C "$BASE_DIR" worktree add -q --detach "$wt" HEAD
    repeat "$RUNS" precommit_once "$wt" || rc=$?
    git -C "$BASE_DIR" worktree remove --force "$wt"
    return "$rc"
}

measure_bats() {
    have bats || { echo n/a; return; }
    local i
    for ((i = 0; i < BATS_RUNS; i++)); do
        ms "$BASE_DIR/bin/run_tests.sh"
    done | median
}

# Bytes every session loads: the rules and this repo's agent notes.
measure_rules() {
    cat "$BASE_DIR"/claudecode/rules/*.md "$BASE_DIR/AGENTS.md" | wc -c | tr -d ' '
}

measure() {
    case "$1" in
        zsh | nvim | tmux | hook | precommit | bats | rules) "measure_$1" ;;
        *)
            echo "speed_report.sh: unknown item: $1" >&2
            exit 2
            ;;
    esac
}

prepare_home
if [ "$#" -gt 0 ]; then
    for item in "$@"; do measure "$item"; done
    exit 0
fi

row="| $(TZ=Asia/Tokyo date +%Y-%m-%d) | $(git -C "$BASE_DIR" rev-parse --short HEAD)"
for item in zsh nvim tmux hook precommit bats rules; do
    row="$row | $(measure "$item")"
done
echo "$row |"
