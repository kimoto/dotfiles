#!/bin/bash
# Interactive end-to-end test for tmux's OWN key bindings (prefix tables) —
# the everyday operations send-keys-into-a-pane cannot reach.
#
# ci_tmux_interactive_test.sh drives the program *inside* a pane (zsh), so a sent
# `M-t` reaches that program, not tmux: send-keys bypasses tmux's key
# interpretation. To exercise bindings we nest tmux: an OUTER tmux (vanilla, so
# its own bindings never interfere) runs a pane whose program is an INNER tmux
# that loads the real .tmux.conf. Keys sent to the OUTER pane are delivered to
# the INNER client as terminal input, so the INNER server interprets them as
# bindings — exactly as a human's keystrokes would. Assertions then query the
# INNER server's state directly (list-windows / display-message), which is far
# more robust than scraping capture-pane.
set -euo pipefail

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/tmux_e2e_helpers.sh"

need tmux
echo "== $(tmux -V) =="

CONF="$(tmux_conf_path)"
echo "== driving bindings from: $CONF =="

OUTER="ci_tmux_kb_out_$$"
INNER="ci_tmux_kb_in_$$"
cleanup() {
  tmux -L "$INNER" kill-server 2>/dev/null || true
  tmux -L "$OUTER" kill-server 2>/dev/null || true
}
trap cleanup EXIT

# Send a key (or key sequence) to the OUTER pane -> reaches the INNER client.
keys() { tmux -L "$OUTER" send-keys "$@"; }
# Number of windows the INNER server currently has.
win_count() { tmux -L "$INNER" list-windows -F '#{window_index}' 2>/dev/null | grep -c .; }
# Active window index on the INNER server.
active_idx() { tmux -L "$INNER" display-message -p '#{window_index}' 2>/dev/null; }

# Poll until win_count equals $1, or time out.
wait_count() {
  local want="$1" tries="${2:-50}" i=0 got
  while [ "$i" -lt "$tries" ]; do
    got="$(win_count || echo 0)"
    [ "$got" = "$want" ] && return 0
    i=$((i + 1)); sleep 0.1
  done
  echo "---- INNER windows at timeout ----" >&2
  tmux -L "$INNER" list-windows >&2 2>/dev/null || true
  die "expected $want windows, saw ${got:-?}"
}

# Poll until the active window index equals $1, or time out.
wait_active() {
  local want="$1" tries="${2:-50}" i=0 got
  while [ "$i" -lt "$tries" ]; do
    got="$(active_idx || true)"
    [ "$got" = "$want" ] && return 0
    i=$((i + 1)); sleep 0.1
  done
  die "expected active window $want, saw ${got:-?}"
}

# OUTER is vanilla (-f /dev/null): its bindings must not shadow the keys we send.
# Its single pane runs the INNER tmux, which loads the config under test.
tmux -L "$OUTER" -f /dev/null new-session -d -x 200 -y 50 \
  "tmux -L '$INNER' -f '$CONF' new-session" ||
  die "failed to start nested tmux"

# Wait for the INNER server to come up (its first window to exist).
wait_count 1
echo "== nested tmux is live =="

# 1) base-index 1 + renumber-windows: the first window is index 1, not 0.
first_idx="$(tmux -L "$INNER" list-windows -F '#{window_index}' | head -n1)"
[ "$first_idx" = "1" ] || die "base-index expected 1, got $first_idx"
echo "== base-index: first window is 1 =="

# 2) Root-table binding `bind -n M-t new-window`: a bare Alt-t opens a window.
keys M-t
wait_count 2
keys M-t
wait_count 3
echo "== M-t opens new windows (3 total) =="

# 3) `bind -n M-2 select-window -t 2`: Alt-2 jumps straight to window 2.
keys M-1   # move away first so the M-2 jump is observable
wait_active 1
keys M-2
wait_active 2
echo "== M-2 selects window 2 =="

# 4) Custom prefix `C-t`: prefix then `c` (tmux's default new-window) works.
keys C-t c
wait_count 4
echo "== custom prefix C-t fires (C-t c -> new window) =="

# 5) `bind-key Right join-pane -t :+`: prefix Right pulls the current window's
#    pane into the next window. The source window then closes, so the window
#    count drops by one and a window ends up with two panes — a genuine
#    pane-management op (not just a window switch) driven entirely by a binding.
keys M-1
wait_active 1
keys C-t Right
wait_count 3
max_panes="$(tmux -L "$INNER" list-windows -F '#{window_panes}' | sort -rn | head -n1)"
[ "$max_panes" = "2" ] || die "join-pane expected a 2-pane window, max was ${max_panes:-?}"
echo "== prefix Right joins a pane (3 windows, one with 2 panes) =="

# 6) `bind-key C-t last-window`: double-tapping the prefix flips back to the
#    window you came from. C-t is the prefix, so this also proves the second
#    C-t is read as a binding rather than being sent on to the pane.
here="$(active_idx)"
there="$(tmux -L "$INNER" list-windows -F '#{window_index}' | grep -v "^${here}$" | head -n1)"
keys "M-${there}"
wait_active "$there"
keys C-t C-t
wait_active "$here"
echo "== prefix C-t returns to the last window =="

# 7) `bind-key C-b send-prefix`, bound *after* tpm: tmux-sensible unbinds C-b
#    whenever it still carries this exact default binding, so a binding placed
#    before the tpm run silently disappears. Wait for the plugins to finish
#    loading first — prefix C-s (tmux-resurrect) is the marker — otherwise the
#    assertion can win a race it should lose.
inner_binding() { tmux -L "$INNER" list-keys -T prefix 2>/dev/null | grep -E "^bind-key +-T prefix +$1 " || true; }
i=0
while [ "$i" -lt 100 ]; do
  [ -n "$(inner_binding 'C-s')" ] && break
  i=$((i + 1)); sleep 0.1
done
[ -n "$(inner_binding 'C-s')" ] || die "tpm plugins never finished loading (no prefix C-s)"
case "$(inner_binding 'C-b')" in
  *send-prefix*) ;;
  *) die "prefix C-b lost its send-prefix binding (tmux-sensible unbound it?)" ;;
esac
echo "== prefix C-b still sends the prefix after tpm =="

# 8) @mru: the hooks stamp a monotonic counter on every pane the user moves to,
#    and prefix+f orders its list by it. Drive two real pane switches through
#    the M-h/M-l bindings, then assert both halves of what the switcher does:
#    the pane just left is ranked ahead of the rest, and the pane you are in is
#    filtered out (it is never a useful jump target).
keys M-t
wait_count 4
tmux -L "$INNER" split-window -h
sleep 0.3
keys M-h; sleep 0.3
left_pane="$(tmux -L "$INNER" display-message -p '#{pane_id}')"
keys M-l; sleep 0.3
cur_pane="$(tmux -L "$INNER" display-message -p '#{pane_id}')"
[ "$left_pane" != "$cur_pane" ] || die "M-h/M-l did not move between panes (both $cur_pane)"
pane_mru() { tmux -L "$INNER" display-message -t "$1" -p '#{?@mru,#{@mru},0}'; }
cur_mru="$(pane_mru "$cur_pane")"; left_mru="$(pane_mru "$left_pane")"
if [ "$left_mru" -lt 1 ] || [ "$cur_mru" -le "$left_mru" ]; then
  die "@mru not stamped in visit order (left=$left_mru, current=$cur_mru)"
fi
# The same filter + sort the prefix+f popup runs; the popup asks the server
# which pane is current, which is what $cur_pane holds here.
switcher_list() {
  TMUX_PANE="$cur_pane" tmux -L "$INNER" list-panes -a \
    -f '#{!=:#{pane_id},'"$cur_pane"'}' \
    -F '#{?@mru,#{@mru},0} #{pane_id}' | sort -rn | cut -d' ' -f2-
}
top="$(switcher_list | head -n1)"
[ "$top" = "$left_pane" ] || die "switcher should rank $left_pane first, got ${top:-empty}"
if switcher_list | grep -qx "$cur_pane"; then
  die "switcher must not offer the current pane $cur_pane"
fi
echo "== prefix+f ranks the last-used pane first and drops the current one =="

echo "PASS"
