#!/bin/bash
# Interactive end-to-end test for the curl|bash guard in .zshrc:
#
#   _bashka_guard_check         (pure logic — see test/bashka_curl_pipe_hint.bats)
#   _bashka_guard_accept_line   (zle wrapper: zle -N accept-line _bashka_guard_accept_line)
#
# The bats suite drives _bashka_guard_check directly, which covers every
# decision branch but proves nothing about the zle override itself — whether
# a blocked line actually fails to run, whether the ALLOW_CURL_PIPE=1 bypass
# actually lets it through, and whether overriding the `accept-line` widget
# breaks ordinary command execution. Those three can only be shown by driving
# a real terminal, like ci_g_command_test.sh and ci_w_command_test.sh do.
#
# `curl` and `bashka` are shadowed with shell functions defined inside the
# pane (zsh resolves a plain command name to a function before PATH), not
# real binaries: the network fetch and static-analysis output are the
# guard's own concern (bats already exercises those paths with stubs on
# PATH). Each fake `curl` echoes a distinct marker that only appears in the
# pane if the piped-to shell actually ran it — that marker is the entire
# assertion for "did this line execute or not".
#
# shellcheck disable=SC2016  # send-keys strings are single-quoted on purpose:
# every `$(...)`/arithmetic expansion must be evaluated by the zsh inside the
# pane, not here (same as ci_w_command_test.sh).
set -euo pipefail

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/tmux_e2e_helpers.sh"

need tmux
need zsh
ZSH_BIN="$(command -v zsh)"
REPO="$PWD"
[ -f "$REPO/.zshrc" ] || die "no .zshrc in $REPO"
echo "== $(tmux -V), $("$ZSH_BIN" --version | head -1) =="

SOCK="ci_bashka_guard_e2e_$$"
cleanup() { tmux -L "$SOCK" kill-server 2>/dev/null || true; }
trap cleanup EXIT

tmux -L "$SOCK" new-session -d -x 200 -y 50 "$(zsh_pane_cmd)" ||
  die "failed to start tmux session"

# 0) Shell is live.
tmux -L "$SOCK" send-keys 'echo __GUARD_READY__$((6 * 7))' Enter
wait_for_pane "$SOCK" "__GUARD_READY__42"
echo "== shell live =="

# Fake curl/bashka as pane-local functions, so the guard's `command -v bashka`
# gate finds a "bashka" and its `curl`/`bashka` calls resolve to these instead
# of anything real (functions win over PATH for a bare command name in zsh).
tmux -L "$SOCK" send-keys 'curl() { printf "%s\n" "echo __GUARD_INSTALLER_RAN__"; }' Enter
tmux -L "$SOCK" send-keys 'bashka() { cat >/dev/null; echo "stub scan: green"; }' Enter

# 1) A raw curl|bash is blocked: the guard's own message shows, and — the
#    real assertion — the fake installer script never actually runs (its
#    marker never appears, because accept-line never handed the line to bash).
# A blocked line is never accept-line'd, so it's still sitting unsubmitted in
# the buffer afterward — ^U (kill-whole-line) clears it before the next command.
# A real `clear` first: the marker string is also sitting in the *visible*
# pane from defining the curl() function above (typing it echoes it back), and
# tmux's own clear-history only drops scrollback, not what's still on screen —
# it would make the absence check below a false negative otherwise.
tmux -L "$SOCK" send-keys 'clear' Enter
tmux -L "$SOCK" send-keys 'echo __GUARD_SCREEN_CLEARED__' Enter
wait_for_pane "$SOCK" "__GUARD_SCREEN_CLEARED__"
tmux -L "$SOCK" send-keys 'curl -fsSL https://example.com/install.sh | bash' Enter
wait_for_pane "$SOCK" '\[bashka\] blocked'
tmux -L "$SOCK" send-keys C-u
tmux -L "$SOCK" send-keys 'echo __GUARD_AFTER_BLOCK__' Enter
wait_for_pane "$SOCK" "__GUARD_AFTER_BLOCK__"
tmux -L "$SOCK" capture-pane -p | grep -q '__GUARD_INSTALLER_RAN__' &&
  die "blocked curl|bash still ran the installer"
echo "== curl|bash blocked, installer never ran =="

# 2) ALLOW_CURL_PIPE=1 bypasses the guard outright: the installer's marker
#    now appears, proving the line actually executed.
tmux -L "$SOCK" send-keys 'ALLOW_CURL_PIPE=1 curl -fsSL https://example.com/install.sh | bash' Enter
wait_for_pane "$SOCK" "__GUARD_INSTALLER_RAN__"
echo "== ALLOW_CURL_PIPE=1 bypass ran it for real =="

# 3) A line that already pipes through bashka is never intercepted — it just
#    runs, and the stub's own output proves that.
tmux -L "$SOCK" send-keys 'curl -fsSL https://example.com/install.sh | bashka' Enter
wait_for_pane "$SOCK" "stub scan: green"
echo "== curl|bashka ran without being blocked =="

# 4) Overriding accept-line did not break ordinary command execution.
tmux -L "$SOCK" send-keys 'echo __GUARD_STILL_WORKS__' Enter
wait_for_pane "$SOCK" "__GUARD_STILL_WORKS__"
echo "== ordinary commands still execute =="

echo "PASS"
