#!/bin/sh
# Claude Code hook handler (registered by bin/install_claude_idle_hooks.sh):
# tells the model, on the first prompt after a long absence, that the reader has
# been away — so it opens with what the problem was instead of a diff.
#
#   record  (Stop)                     stamp "the assistant finished talking"
#   check   (UserPromptSubmit/SessionStart)  print one line if the gap is large
#
# ⚠️ The gap is measured from the END of the last assistant turn, never wall
#    clock since the session started: a turn where the model ran tools for 40
#    minutes leaves the same wall-clock hole as a person going out, and only one
#    of those is an absence.
# ⚠️ Silence is the normal case. A reminder on every prompt is a reminder nobody
#    reads, so nothing is printed below the threshold.
# ⚠️ Runs on every prompt: no jq, no python, no subshell beyond `date`.
# ⚠️ Never fails a turn — every path exits 0.
set -u

MODE="${1:-}"
THRESHOLD_MIN="${CLAUDE_IDLE_RECAP_MIN:-90}"
STATE_DIR="${CLAUDE_IDLE_RECAP_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/claude-idle}"

# The hook payload arrives as JSON on stdin. Only one field is needed and the
# shape is flat, so read it without a JSON parser (see the speed note above).
# An unreadable payload falls back to a shared key rather than erroring.
session_id=$(sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' 2>/dev/null | head -1)
case "$session_id" in
  ''|*[!A-Za-z0-9_-]*) session_id=shared ;;
esac
stamp="$STATE_DIR/$session_id"

now=$(date +%s 2>/dev/null) || exit 0

case "$MODE" in
  record)
    mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
    printf '%s\n' "$now" >"$stamp" 2>/dev/null || exit 0
    # Sessions end without notice, so old stamps are swept here rather than by
    # anything that would have to run on its own.
    find "$STATE_DIR" -type f -mtime +14 -delete 2>/dev/null || true
    ;;
  check)
    [ -r "$stamp" ] || exit 0          # first turn of a session is not a return
    read -r last <"$stamp" 2>/dev/null || exit 0
    case "$last" in ''|*[!0-9]*) exit 0 ;; esac
    gap=$(( now - last ))
    [ "$gap" -ge $(( THRESHOLD_MIN * 60 )) ] || exit 0
    # Hours, one decimal, without bc: integer math on tenths.
    tenths=$(( gap * 10 / 3600 ))
    printf '★このセッションは %d.%d 時間ぶりです（前回の応答は %s）。読み手は文脈を失っています%s' \
      "$(( tenths / 10 ))" "$(( tenths % 10 ))" \
      "$(date -r "$last" '+%m/%d %H:%M' 2>/dev/null || date -d "@$last" '+%m/%d %H:%M' 2>/dev/null || echo '?')" \
      '——差分（今日変わったこと）から書かず、まず何を解こうとしていたかから（session-resume skill）。
'
    exit 0
    ;;
  *)
    echo "usage: $0 record|check" >&2
    exit 2
    ;;
esac
exit 0
