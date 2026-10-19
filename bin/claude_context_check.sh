#!/bin/sh
# Claude Code UserPromptSubmit hook (registered by
# bin/install_claude_context_hooks.sh): once the context has grown long, tells
# both the person and the model that it is time to hand off to a fresh session
# — via the handoff skill — instead of letting auto-compact replace the
# conversation with a summary that silently drops detail.
#
# The size is the last main-chain assistant turn's input (uncached + cache
# write + cache read), read from the transcript.
# ★The thresholds are token counts, not shares of the compact window. Compact is
#  only the backstop, left at Claude Code's default; when to hand off is decided
#  here. Every turn re-reads the whole context, so cost and slowness grow with
#  its size whatever the window is.
#
# ⚠️ Each threshold speaks once per climb. A notice on every prompt is a notice
#    nobody reads; a drop below a threshold (compact, /clear) re-arms it.
# ⚠️ It never interrupts the work in progress: the model is told to propose the
#    handoff at the next break, not to stop.
# ⚠️ Runs on every prompt: it reads only the transcript's tail.
# ⚠️ Never fails a turn — every path exits 0.
set -u

# 400K: early enough that the handoff is a choice, not a rescue. 600K: stop
# starting new work while a handoff still fits before compact (~800K on a 1M
# model in a cloud session), and before the length where published long-context
# results show clear losses (~800K). Not measured on our own sessions; lower
# values landed mid-task and went unread.
WARN_TOKENS="${CLAUDE_CONTEXT_WARN_TOKENS:-400000 600000}"
STATE_DIR="${CLAUDE_CONTEXT_CHECK_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/claude-context}"

command -v jq >/dev/null 2>&1 || exit 0

payload=$(cat 2>/dev/null) || exit 0
session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)
transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)
case "$session_id" in
  ''|*[!A-Za-z0-9_-]*) exit 0 ;;
esac
[ -r "$transcript" ] || exit 0

# fromjson? skips a line that does not parse (a write in flight) instead of
# ending the stream there.
used=$(tail -n 100 "$transcript" 2>/dev/null | jq -Rr '
  fromjson? | select(.type == "assistant" and (.isSidechain | not))
  | .message.usage // empty
  | (.input_tokens // 0) + (.cache_creation_input_tokens // 0)
    + (.cache_read_input_tokens // 0)' 2>/dev/null | tail -n 1)
case "$used" in ''|*[!0-9]*) exit 0 ;; esac

level=0
for t in $WARN_TOKENS; do
  case "$t" in ''|*[!0-9]*) continue ;; esac
  [ "$used" -ge "$t" ] && level=$(( level + 1 ))
done

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
state="$STATE_DIR/$session_id"
last=0
[ -r "$state" ] && read -r last <"$state" 2>/dev/null
case "$last" in ''|*[!0-9]*) last=0 ;; esac
printf '%s\n' "$level" >"$state" 2>/dev/null || exit 0
# Sessions end without notice, so old state is swept here.
find "$STATE_DIR" -type f -mtime +14 -delete 2>/dev/null || true
[ "$level" -gt "$last" ] || exit 0

size="$(( used / 1000 ))k"
if [ "$level" -eq 1 ]; then
  user="コンテキスト $size。区切りで次のセッションへの仕切り直しを検討"
  model="★コンテキストが $size トークンに達した。今の作業は止めずに続け、"
  model="${model}次に区切りが付いた返答の末尾で一行、仕切り直しを提案する: "
  model="${model}handoff skill で次のセッションに貼る引き継ぎプロンプトを作る。"
else
  user="コンテキスト $size。今の作業単位を閉じたら仕切り直し"
  model="★コンテキストが $size トークン。新しい大きな作業は始めない。"
  model="${model}今の作業単位を閉じたら handoff skill を実行し、引き継ぎプロンプトを渡して仕切り直しを勧める。"
  model="${model}自動 compact は会話を要約に置き換え、細部が黙って落ちる。"
fi

jq -nc --arg user "$user" --arg model "$model" '{
  systemMessage: $user,
  hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $model}
}' 2>/dev/null
exit 0
