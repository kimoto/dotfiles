#!/usr/bin/env bats

# Tests for bin/claude_find_session.sh: find a Claude Code session by words in
# its transcript and resume it in the directory it ran in. A fake `fzf` takes
# the first row; a fake `claude` records its directory and arguments.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/claude_find_session.sh"
  TMP="$(mktemp -d)"
  export HOME="$TMP/home"
  unset CLAUDE_CONFIG_DIR
  PROJECTS="$HOME/.claude/projects"
  mkdir -p "$TMP/bin" "$HOME/.local/bin" "$TMP/work/a" "$TMP/work/b" \
    "$PROJECTS/-work-a" "$PROJECTS/-work-b"

  cat >"$HOME/.local/bin/claude" <<'SH'
#!/bin/sh
printf '%s %s\n' "$PWD" "$*" >"$CALLS"
SH
  cat >"$TMP/bin/fzf" <<'SH'
#!/bin/sh
cat >"$ROWS"
head -1 "$ROWS"
SH
  chmod +x "$HOME/.local/bin/claude" "$TMP/bin/fzf"
  export CALLS="$TMP/calls" ROWS="$TMP/rows"
  PATH="$TMP/bin:$PATH"
}

teardown() {
  rm -rf "$TMP"
}

# transcript <project dir> <session id> <cwd> <text said in it>
transcript() {
  local stamp='"timestamp":"2026-10-31T09:15:00.000Z"'
  printf '{"type":"user","cwd":"%s","sessionId":"%s",%s,"message":{"content":"%s"}}\n' \
    "$3" "$2" "$stamp" "$4" >"$PROJECTS/$1/$2.jsonl"
}

@test "resumes the session that said the words, in its own directory" {
  transcript -work-a s-a "$TMP/work/a" "tune the tmux status line"
  transcript -work-b s-b "$TMP/work/b" "fix the Ghostty copy on select default"
  run "$SCRIPT" ghostty COPY
  [ "$status" -eq 0 ]
  [ "$(cat "$CALLS")" = "$TMP/work/b --resume s-b" ]
  [ "$(wc -l <"$ROWS")" -eq 1 ]
  grep -q $'\t2026-10-31 09:15\t' "$ROWS"
}

@test "the newest session is offered first" {
  transcript -work-a s-old "$TMP/work/a" "deploy notes"
  transcript -work-b s-new "$TMP/work/b" "deploy notes"
  touch -t 202601010000 "$PROJECTS/-work-a/s-old.jsonl"
  run "$SCRIPT" deploy
  [ "$status" -eq 0 ]
  [ "$(cat "$CALLS")" = "$TMP/work/b --resume s-new" ]
}

@test "a subagent transcript is not offered on its own" {
  mkdir -p "$PROJECTS/-work-a/s-a/subagents"
  transcript -work-a s-a "$TMP/work/a" "nothing here"
  printf '{"cwd":"%s","message":"needle"}\n' "$TMP/work/a" >"$PROJECTS/-work-a/s-a/subagents/agent-1.jsonl"
  run "$SCRIPT" needle
  [ "$status" -eq 1 ]
  [ ! -e "$CALLS" ]
}

@test "regex characters in the words are matched literally" {
  transcript -work-a s-a "$TMP/work/a" "run a.b(c) now"
  transcript -work-b s-b "$TMP/work/b" "run axb(c) now"
  run "$SCRIPT" 'a.b(c)'
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$ROWS")" -eq 1 ]
  grep -q 'run a.b(c) now' "$ROWS"
}

@test "a session whose directory is gone is named, not resumed" {
  transcript -work-a s-a "$TMP/work/gone" "the removed worktree"
  run "$SCRIPT" removed
  [ "$status" -eq 1 ]
  [[ "$output" == *"claude --resume s-a"* ]]
  [ ! -e "$CALLS" ]
}

@test "no words is a usage error" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
}
