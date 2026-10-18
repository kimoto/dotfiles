#!/bin/sh
# Carries a handoff across `/clear` (registered by
# bin/install_claude_context_hooks.sh; `save` is called by the handoff skill):
#
#   save   (handoff skill, stdin)  park the handoff prompt for this directory
#   end    (SessionEnd hook)       on /clear, note the transcript being left
#   start  (SessionStart hook)     on /clear, hand both to the new session
#
# So the person only types /clear: no copy, no paste. The old transcript is
# passed by path, not content, so the new session reads only what it needs.
#
# Keyed by working directory: /clear keeps it, and the hook payloads carry it.
# ⚠️ Two sessions in one directory share the slot; the last /clear takes it.
#    One worktree per session (AGENTS.md) already avoids that.
# ⚠️ Only source/reason "clear" counts. A fresh `claude` in the same directory
#    is a new piece of work and must not inherit a stale handoff.
# ⚠️ Never fails a session — every hook path exits 0.
set -u

MODE="${1:-}"
STATE_DIR="${CLAUDE_HANDOFF_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/claude-handoff}"
# A handoff nobody picked up within a day belongs to work that moved on.
MAX_AGE_MIN=1440

key_for() { printf '%s' "$1" | tr -c 'A-Za-z0-9' '-'; }

umask 077

case "$MODE" in
  save)
    mkdir -p "$STATE_DIR" || exit 1
    f="$STATE_DIR/$(key_for "$PWD").md"
    cat >"$f" || exit 1
    [ -s "$f" ] || { rm -f "$f"; echo "claude_handoff: empty handoff" >&2; exit 1; }
    echo "saved: $f"
    exit 0
    ;;
  end|start) ;;
  *)
    echo "usage: $0 save|end|start" >&2
    exit 2
    ;;
esac

command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat 2>/dev/null) || exit 0
field() { printf '%s' "$payload" | jq -r --arg k "$1" '.[$k] // empty' 2>/dev/null; }
cwd=$(field cwd)
[ -n "$cwd" ] || exit 0
base="$STATE_DIR/$(key_for "$cwd")"

if [ "$MODE" = end ]; then
  [ "$(field reason)" = clear ] || exit 0
  transcript=$(field transcript_path)
  [ -n "$transcript" ] || exit 0
  mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
  printf '%s\n' "$transcript" >"$base.prev" 2>/dev/null
  exit 0
fi

[ "$(field source)" = clear ] || exit 0
find "$STATE_DIR" -type f -mmin +"$MAX_AGE_MIN" -delete 2>/dev/null
prev=
[ -r "$base.prev" ] && read -r prev <"$base.prev"
handoff=
[ -r "$base.md" ] && handoff=$(cat "$base.md")
rm -f "$base.prev" "$base.md"
[ -n "$prev$handoff" ] || exit 0

if [ -n "$handoff" ]; then
  user="前のセッションの引き継ぎを読み込んだ"
  model="★直前のセッションが /clear の前に残した引き継ぎ。これを今回の作業の出発点にする:

$handoff"
else
  user="前のセッションの transcript を参照できる"
  model="★このセッションは /clear の直後。"
fi
if [ -n "$prev" ]; then
  model="$model

前のセッションの transcript: $prev
（JSONL。引き継ぎに無いことが要るときだけ、rg や jq で該当箇所を探して読む。丸ごと読まない）"
fi

jq -nc --arg user "$user" --arg model "$model" '{
  systemMessage: $user,
  hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $model}
}' 2>/dev/null
exit 0
