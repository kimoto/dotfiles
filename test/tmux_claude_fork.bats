#!/usr/bin/env bats

# Tests for bin/tmux_claude_fork.sh, tmux's prefix + A.
#
# The fork must carry the parent's --permission-mode and --model, or the
# changed system prompt misses the prompt cache and the whole context is sent
# again. Fake `tmux`, `ps` and `lsof` on PATH stand in for the live session; a
# sleeping process stands in for the parent so `kill -0` finds it alive.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/tmux_claude_fork.sh"
  TMP="$(mktemp -d)"
  export HOME="$TMP/home"
  mkdir -p "$TMP/bin" "$HOME/.local/bin" "$TMP/state"
  printf '#!/bin/sh\n' >"$HOME/.local/bin/claude"
  chmod +x "$HOME/.local/bin/claude"

  cat >"$TMP/bin/tmux" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$CALLS"
[ "$1" = new-pane ] && echo '%9'
exit 0
EOF
  cat >"$TMP/bin/ps" <<'EOF'
#!/bin/sh
printf '%s\n' "$PARENT_ARGS"
EOF
  printf '#!/bin/sh\n' >"$TMP/bin/lsof"
  chmod +x "$TMP/bin/tmux" "$TMP/bin/ps" "$TMP/bin/lsof"
  export CALLS="$TMP/calls"
  export TMUX_ASSISTANT_RESURRECT_DIR="$TMP/state"
  PATH="$TMP/bin:$PATH"

  sleep 300 &
  PARENT=$!
}

teardown() {
  kill "$PARENT" 2>/dev/null || true
  rm -rf "$TMP"
}

write_state() {
  printf '{"session_id":"abc123","cwd":"%s","env":{"tmux_pane":"%%1"}}\n' "$TMP" \
    >"$TMP/state/claude-$PARENT.json"
}

@test "the fork carries the parent's permission mode and model" {
  write_state
  export PARENT_ARGS="claude --permission-mode acceptEdits --model=opus"
  run "$SCRIPT" %1
  [ "$status" -eq 0 ]
  grep -q "^new-pane .* --fork-session --resume abc123 --permission-mode acceptEdits --model opus$" "$CALLS"
}

@test "a parent with neither flag forks with neither" {
  write_state
  export PARENT_ARGS="claude"
  run "$SCRIPT" %1
  [ "$status" -eq 0 ]
  grep -q "^new-pane .* --fork-session --resume abc123$" "$CALLS"
}

@test "a pane with no live session says so instead of opening a float" {
  export PARENT_ARGS="claude"
  run "$SCRIPT" %1
  [ "$status" -eq 0 ]
  grep -q "^display-message claude fork: no live claude session in %1$" "$CALLS"
  ! grep -q "^new-pane" "$CALLS"
}
