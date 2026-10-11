#!/bin/sh
# Claude Code hook handler (registered by bin/install_claude_tmux_hooks.sh):
# keep the hunk pane that prefix + v opened beside Claude pointed at the repo
# Claude is working in. Entering a worktree moves Claude but not that pane, so
# without this it keeps watching a checkout nobody is editing.
#
# Reads the hook JSON on stdin. The directory comes from `new_cwd` (CwdChanged,
# a `cd` in Bash) or `cwd` (PostToolUse on EnterWorktree/ExitWorktree, which
# CwdChanged does not fire for; `cwd` is already the new directory there).
# Only panes in Claude's own window are touched, and only when they watch a
# different repo, so a `cd` within the same repo restarts nothing.
# Outside tmux this is a silent no-op: a hook must never break a session.
set -eu

# What .tmux.conf's prefix + v runs; the only way to tell a hunk pane apart.
HUNK_CMD="hunk diff --watch"

[ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

dir="$(jq -r '.new_cwd // .cwd // empty' 2>/dev/null || true)"
[ -n "$dir" ] || exit 0
top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || exit 0

tab="$(printf '\t')"
tmux list-panes -t "$TMUX_PANE" \
    -F "#{pane_id}${tab}#{pane_current_path}${tab}#{pane_start_command}" 2>/dev/null |
  while IFS="$tab" read -r id path cmd; do
    # tmux reports the start command wrapped in double quotes.
    case "$cmd" in *"$HUNK_CMD"*) ;; *) continue ;; esac
    [ "$(git -C "$path" rev-parse --show-toplevel 2>/dev/null || true)" != "$top" ] || continue
    tmux respawn-pane -k -t "$id" -c "$top" "$HUNK_CMD" 2>/dev/null || true
  done
