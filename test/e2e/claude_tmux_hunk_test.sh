#!/bin/bash
# End-to-end test for the hook that keeps hunk panes on Claude's repo: runs
# the real handler (bin/claude_tmux_hunk.sh) against a real tmux server loaded
# with the repo .tmux.conf, with a stub `hunk` that only sleeps — the test is
# about which directory a pane is restarted in, and with which command, not
# about hunk.
set -euo pipefail

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/tmux_e2e_helpers.sh"

need tmux
need git
need jq
echo "== $(tmux -V) =="

CONF="$(tmux_conf_path)"
HUNK_CMD="hunk diff --watch"
BRANCH_CMD="hunk_branch_diff.sh"

TMP="$(mktemp -d)"
SOCK="ci_claude_hunk_$$"
cleanup() { tmux -L "$SOCK" kill-server 2>/dev/null || true; rm -rf "$TMP"; }
trap cleanup EXIT

mkdir -p "$TMP/stub" "$TMP/plain"
printf '#!/bin/sh\nexec sleep 300\n' >"$TMP/stub/hunk"
chmod +x "$TMP/stub/hunk"
# Exported, not set on the server: a new pane takes PATH from the client that
# asked for it, and the respawns come from the handler, as they do for Claude.
export PATH="$TMP/stub:$PATH"
for r in A B; do
  git init -q "$TMP/$r"
  mkdir -p "$TMP/$r/sub"
done
A="$(cd -P "$TMP/A" && pwd)"
B="$(cd -P "$TMP/B" && pwd)"

# 0) prefix + v / V must still start exactly what the handler looks for.
tmux -L "$SOCK" -f "$CONF" new-session -d -s HUNK -c "$A" -x 200 -y 50 \
  || die "failed to start tmux"
disable_continuum_restore "$SOCK"
binding() { tmux -L "$SOCK" list-keys -T prefix | grep -E "^bind-key +-T prefix +$1 " || true; }
case "$(binding v)" in
  *"$HUNK_CMD"*) ;;
  *) die "prefix + v is now '$(binding v)', not '$HUNK_CMD'; update the match in claude_tmux_hunk.sh" ;;
esac
case "$(binding V)" in
  *"$BRANCH_CMD"*) ;;
  *) die "prefix + V is now '$(binding V)', not $BRANCH_CMD; update the match in claude_tmux_hunk.sh" ;;
esac
echo "== prefix + v / V still run what the handler looks for =="

# A pane that dies stays, so a failure can say why.
tmux -L "$SOCK" set-option -g remain-on-exit on

SOCK_PATH="$(tmux -L "$SOCK" display-message -p '#{socket_path}')"
CLAUDE="$(tmux -L "$SOCK" display-message -p '#{pane_id}')"
HUNK="$(tmux -L "$SOCK" split-window -h -P -F '#{pane_id}' -c "$A" "$HUNK_CMD")"
BRANCH="$(tmux -L "$SOCK" split-window -v -P -F '#{pane_id}' -c "$A" "$DIR/$BRANCH_CMD")"
OTHER="$(tmux -L "$SOCK" new-window -d -P -F '#{pane_id}' -c "$A" "$HUNK_CMD")"

# Run the handler the way Claude Code does: hook JSON on stdin, tmux only
# known through $TMUX / $TMUX_PANE.
hook() { printf '%s' "$1" | TMUX="$SOCK_PATH,0,0" TMUX_PANE="$CLAUDE" "$DIR/claude_tmux_hunk.sh"; }
path_of() { tmux -L "$SOCK" display-message -p -t "$1" '#{pane_current_path}'; }
pid_of() { tmux -L "$SOCK" display-message -p -t "$1" '#{pane_pid}'; }
wait_path() { # <pane> <expected> <label>
  local i=0
  while [ "$i" -lt 50 ]; do
    [ "$(path_of "$1")" = "$2" ] && return 0
    i=$((i + 1)); sleep 0.1
  done
  die "$3: expected $1 in '$2', got '$(path_of "$1")'" \
    "($(tmux -L "$SOCK" display-message -p -t "$1" 'dead=#{pane_dead} status=#{pane_dead_status}'))"
}

wait_path "$HUNK" "$A" "setup"
wait_path "$BRANCH" "$A" "setup (V)"
for p in "$HUNK" "$BRANCH"; do
  i=0
  until [ "$(tmux -L "$SOCK" display-message -p -t "$p" '#{pane_current_command}')" = sleep ]; do
    i=$((i + 1))
    [ "$i" -lt 50 ] || die "setup: $p runs" \
      "'$(tmux -L "$SOCK" display-message -p -t "$p" '#{pane_current_command}')', not the stub hunk"
    sleep 0.1
  done
done
start_of() { tmux -L "$SOCK" display-message -p -t "$1" '#{pane_start_command}'; }

# 1) EnterWorktree: PostToolUse carries the new directory in `cwd`.
hook "{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"EnterWorktree\",\"cwd\":\"$B\"}"
wait_path "$HUNK" "$B" "EnterWorktree"
start_of "$HUNK" | grep -qF "$HUNK_CMD" \
  || die "EnterWorktree: the respawned v pane no longer runs '$HUNK_CMD'"
wait_path "$BRANCH" "$B" "EnterWorktree (V)"
start_of "$BRANCH" | grep -qF "$BRANCH_CMD" \
  || die "EnterWorktree: the respawned V pane runs '$(start_of "$BRANCH")', not $BRANCH_CMD"
echo "== EnterWorktree moves both hunk panes, each keeping its own command =="

# 2) A hunk pane in another window is not Claude's and stays put.
[ "$(path_of "$OTHER")" = "$A" ] || die "other window: hunk pane moved to '$(path_of "$OTHER")'"
echo "== a hunk pane in another window is left alone =="

# 3) A cd within the same repo restarts nothing.
pid="$(pid_of "$HUNK")"
hook "{\"hook_event_name\":\"CwdChanged\",\"old_cwd\":\"$B\",\"new_cwd\":\"$B/sub\",\"cwd\":\"$B/sub\"}"
[ "$(pid_of "$HUNK")" = "$pid" ] || die "same-repo cd: hunk was restarted"
echo "== a cd within the same repo leaves hunk running =="

# 4) A cd out of any repo leaves hunk where it is.
hook "{\"hook_event_name\":\"CwdChanged\",\"new_cwd\":\"$TMP/plain\",\"cwd\":\"$TMP/plain\"}"
[ "$(pid_of "$HUNK")" = "$pid" ] || die "non-repo cd: hunk was restarted"
echo "== a cd out of any repo leaves hunk running =="

# 5) CwdChanged into another repo: the directory comes from `new_cwd`.
hook "{\"hook_event_name\":\"CwdChanged\",\"old_cwd\":\"$B\",\"new_cwd\":\"$A/sub\",\"cwd\":\"$B\"}"
wait_path "$HUNK" "$A" "CwdChanged"
echo "== CwdChanged into another repo moves hunk to that repo's root =="

# 6) Outside tmux the handler is a silent no-op.
out="$(printf '{"cwd":"%s"}' "$B" | env -u TMUX -u TMUX_PANE "$DIR/claude_tmux_hunk.sh" 2>&1)" \
  || die "outside tmux: exited non-zero"
[ -z "$out" ] || die "outside tmux: printed '$out'"
echo "== outside tmux it is a silent no-op =="

echo "== all hunk-follow checks passed =="
