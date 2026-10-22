#!/bin/bash

# Draw what .tmux.conf looks like on screen and compare it with the look we
# last accepted, so an upstream tmux release that changes the look shows up as
# a diff instead of as a surprise on a workstation. tmux 3.8 changing the
# default window-status-current-style to underscore is the case this exists
# for: every option still read back the same, and only the drawn status line
# had an underline.
#
# Usage:
#   tmux_render_snapshot.sh print    the rendering, on stdout
#   tmux_render_snapshot.sh check    compare with the golden; exit 1 and print
#                                    the diff if they differ
#   tmux_render_snapshot.sh update   rewrite the golden from this tmux
#   tmux_render_snapshot.sh raw      the screens with their escape codes, to
#                                    look at in a terminal (not compared)
#   tmux_render_snapshot.sh normalize   rewrite capture-pane -e output read
#                                    on stdin the way print does (for tests)
# TMUX_BIN picks the tmux under test (default: tmux on PATH, Homebrew's first).
#
# The golden is drawn by the latest tmux release: CI's tmux_latest_test runs
# `check` there, so a new release that draws differently turns it red. A
# difference is not always a regression — a release can improve the look —
# so the answer is either a .tmux.conf change that restores it or `update`,
# and a person picks which in review. Older tmux releases draw some things
# differently (no copy-mode line numbers before 3.7), so `check` is only
# meaningful on the release the golden was drawn with.
#
# How it draws: a second tmux server (the "outer" one, no config) runs a
# client of the server under test inside its only pane, and capture-pane -e on
# that pane returns every cell the client drew, status line included, which
# capture-pane on the server under test cannot. The cells are then rewritten as
# runs of `[style]text`, so the golden reads as text and the diff points at
# the cell that moved rather than at an escape sequence.
#
# The server under test loads .tmux.conf under a throwaway HOME (no plugins,
# no ~/.tmux.conf.local), with fixed names, titles and pane text; the clock is
# replaced by a placeholder. Two draws of the same config print the same bytes.

set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
GOLDEN="$BASE_DIR/test/fixtures/tmux_render.txt"

# shellcheck source=bin/brew_lib.sh
. "$BASE_DIR/bin/brew_lib.sh"
load_brew
TMUX_BIN="${TMUX_BIN:-tmux}"
# The config's run-shell scripts call plain `tmux`; they must reach the server
# under test with the same release, not whatever else is on PATH.
case "$TMUX_BIN" in
    */*) PATH="$(cd "$(dirname "$TMUX_BIN")" && pwd):$PATH" ;;
esac

# The screen the client draws on. Wide enough that the status line shows every
# window and the whole right side; tall enough for two bordered panes.
COLS=110
ROWS=12

usage() {
    echo "usage: tmux_render_snapshot.sh print|check|update|raw|normalize" >&2
    exit 2
}

INNER="render_inner_$$"
OUTER="render_outer_$$"
HOME_DIR=""
cleanup() {
    "$TMUX_BIN" -L "$OUTER" kill-server 2>/dev/null || true
    "$TMUX_BIN" -u -L "$INNER" kill-server 2>/dev/null || true
    [ -z "$HOME_DIR" ] || rm -rf "$HOME_DIR"
}
trap cleanup EXIT

in_tmux() { HOME="$HOME_DIR" "$TMUX_BIN" -u -L "$INNER" "$@"; }
out_tmux() { "$TMUX_BIN" -u -L "$OUTER" "$@"; }

# Each pane runs a fixed text and then waits, so nothing in it moves.
pane_cmd() { printf "sh -c 'printf \"%s\"; exec sleep 100000'" "$1"; }

start() {
    HOME_DIR=$(mktemp -d)
    ln -s "$BASE_DIR/.tmux.conf" "$HOME_DIR/.tmux.conf"
    ln -s "$BASE_DIR/config" "$HOME_DIR/.config"

    in_tmux new-session -d -s work -n editor -x "$COLS" -y "$ROWS" \
        "$(pane_cmd 'first line\nsecond line\nthird line\n')"
    in_tmux set -g @continuum-restore off
    # The window list covers each way a tab can look: current, bell, an agent
    # waiting on the user, zoomed, and plain.
    in_tmux split-window -h -t work:1 "$(pane_cmd 'right pane\n')"
    in_tmux select-pane -t work:1.1 -T left \; select-pane -t work:1.2 -T right
    in_tmux new-window -d -t work:2 -n logs "$(pane_cmd '\a')"
    in_tmux new-window -d -t work:3 -n agent "$(pane_cmd '')"
    # As state.sh marks a waiting agent: the pane state first, since the
    # window-linked hook recomputes @agent_color from it in the background
    # and would otherwise race a plain set back to empty.
    in_tmux set -p -t work:3.1 @agent_state waiting \; \
        set -wF -t work:3 @agent_color '#{E:@agent_win_color}'
    in_tmux new-window -d -t work:4 -n zoomed "$(pane_cmd '')"
    in_tmux split-window -d -t work:4 "$(pane_cmd '')"
    in_tmux resize-pane -Z -t work:4.1
    in_tmux new-window -d -t work:5 -n plain "$(pane_cmd '')"
    in_tmux select-window -t work:1 \; select-pane -t work:1.1

    out_tmux -f /dev/null new-session -d -x "$COLS" -y "$ROWS" \
        "env HOME='$HOME_DIR' TERM=tmux-256color '$TMUX_BIN' -u -L '$INNER' attach -t work"
    out_tmux set -g status off
    settle
}

# Wait until the client has drawn what the last key asked for. A fixed sleep
# would be either slow or flaky; this waits for two identical captures.
settle() {
    local prev="" cur i
    for i in $(seq 1 50); do
        sleep 0.1
        cur=$(out_tmux capture-pane -e -p -t 0 2>/dev/null || true)
        if [ -n "$cur" ] && [ "$cur" = "$prev" ] && [ "$i" -ge 5 ]; then
            return 0
        fi
        prev="$cur"
    done
}

capture() { out_tmux capture-pane -e -p -t 0; }

# keys <key>...: press keys on the client, the way a person would.
keys() { out_tmux send-keys -t 0 "$@"; settle; }

# screens: each state worth seeing, under a header naming it.
screens() {
    start
    echo "== normal =="
    capture
    echo "== prefix held (status line) =="
    keys C-t
    capture | tail -n 1
    keys Escape
    echo "== copy mode =="
    keys C-t [
    capture
    keys q
}

# normalize: rewrite capture-pane -e output as runs of [style]text, one run per
# change of style. A run of spaces drops its fg, which no one can see, unless
# an attribute draws something on a space (underscore, reverse, strike,
# overline); the 3.8 status line moved an invisible fg onto padding, and that
# is not a change in the look. The clock becomes <clock>.
normalize() {
    LC_ALL=C awk '
    function reset() { fg = ""; bg = ""; delete at }
    function style(   s, k, n, i, keys) {
        n = 0
        for (k in at) keys[++n] = k
        # insertion sort: awk has no portable sort
        for (i = 2; i <= n; i++) {
            k = keys[i]
            for (j = i - 1; j >= 1 && keys[j] > k; j--) keys[j + 1] = keys[j]
            keys[j + 1] = k
        }
        s = ""
        for (i = 1; i <= n; i++) s = s " " keys[i]
        return s
    }
    function color(p, i,   v) {
        if (p[i] == 2) { v = sprintf("#%02x%02x%02x", p[i+1], p[i+2], p[i+3]); used = 4 }
        else if (p[i] == 5) { v = "colour" p[i+1]; used = 2 }
        else { v = "?"; used = 0 }
        return v
    }
    function sgr(params,   p, n, i, c) {
        if (params == "") params = "0"
        n = split(params, p, ";")
        for (i = 1; i <= n; i++) {
            c = p[i]
            if (c == 0) reset()
            else if (c == 1) at["bold"] = 1
            else if (c == 2) at["dim"] = 1
            else if (c == 3) at["italics"] = 1
            else if (c == 4 || c ~ /^4:[1-5]$/) at["underscore" (c ~ /:/ ? substr(c, 3) : "")] = 1
            else if (c == "4:0") { for (k in at) if (k ~ /^underscore/) delete at[k] }
            else if (c == 5) at["blink"] = 1
            else if (c == 7) at["reverse"] = 1
            else if (c == 8) at["hidden"] = 1
            else if (c == 9) at["strike"] = 1
            else if (c == 21) at["double-underscore"] = 1
            else if (c == 53) at["overline"] = 1
            else if (c == 22) { delete at["bold"]; delete at["dim"] }
            else if (c == 23) delete at["italics"]
            else if (c == 24) { for (k in at) if (k ~ /underscore/) delete at[k] }
            else if (c == 25) delete at["blink"]
            else if (c == 27) delete at["reverse"]
            else if (c == 28) delete at["hidden"]
            else if (c == 29) delete at["strike"]
            else if (c == 55) delete at["overline"]
            else if (c >= 30 && c <= 37) fg = "colour" (c - 30)
            else if (c >= 90 && c <= 97) fg = "colour" (c - 90 + 8)
            else if (c == 39) fg = ""
            else if (c >= 40 && c <= 47) bg = "colour" (c - 40)
            else if (c >= 100 && c <= 107) bg = "colour" (c - 100 + 8)
            else if (c == 49) bg = ""
            else if (c == 38) { fg = color(p, i + 1); i += used }
            else if (c == 48) { bg = color(p, i + 1); i += used }
            else at["sgr" c] = 1
        }
    }
    function visible_on_space(   k) {
        for (k in at) if (k ~ /underscore|reverse|strike|overline/) return 1
        return 0
    }
    function emit(text,   s) {
        if (text == "") return
        s = (bg != "" ? " bg=" bg : "")
        if (text !~ /^ +$/ || visible_on_space()) s = (fg != "" ? " fg=" fg : "") s
        s = substr(s style(), 2)
        if (s == cur) { buf = buf text; return }
        flush()
        cur = s; buf = text
    }
    function flush() {
        if (buf != "") out = out "[" cur "]" buf
        buf = ""
    }
    /^== .* ==$/ { print; reset(); next }
    {
        out = ""; buf = ""; cur = "\001"
        n = split($0, part, "\033\\[")
        emit(part[1])
        for (i = 2; i <= n; i++) {
            m = match(part[i], /^[0-9:;]*m/)
            if (m) { sgr(substr(part[i], 1, RLENGTH - 1)); emit(substr(part[i], RLENGTH + 1)) }
            else emit("\033[" part[i])
        }
        # capture-pane trims trailing blanks drawn in the default style, but
        # not those it drew after the last change of style; trim those too.
        if (cur == "") sub(/ +$/, "", buf)
        flush()
        print out
    }' | sed -E 's/[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}/<clock>/g'
}

case "${1:-}" in
    print) screens | normalize ;;
    raw) screens ;;
    normalize) normalize ;;
    update)
        screens | normalize >"$GOLDEN"
        echo "wrote $GOLDEN from $("$TMUX_BIN" -V)"
        ;;
    check)
        actual=$(screens | normalize)
        if ! diff -u --label "golden ($GOLDEN)" --label "$("$TMUX_BIN" -V)" \
                "$GOLDEN" <(printf '%s\n' "$actual"); then
            echo "The look of .tmux.conf changed on $("$TMUX_BIN" -V)." >&2
            echo "Restore it in .tmux.conf, or accept it with: $0 update" >&2
            exit 1
        fi
        echo "== $("$TMUX_BIN" -V) draws .tmux.conf as the golden does =="
        ;;
    *) usage ;;
esac
