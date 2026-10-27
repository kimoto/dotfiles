#!/usr/bin/env bats

# Tests for bin/ghq_pick.sh (`g`) and bin/tmux_repo_window.sh (prefix + G).
#
# Fake `ghq`, `zoxide`, `fzf` and `tmux` on PATH. The fake fzf takes the first
# candidate, so the ranking decides what gets picked.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  PICK="$REPO_ROOT/bin/ghq_pick.sh"
  WINDOW="$REPO_ROOT/bin/tmux_repo_window.sh"
  TMP="$(mktemp -d)"
  export ROOT="$TMP/ghq" CALLS="$TMP/calls" ZOXIDE="$TMP/zoxide" PANES="$TMP/panes"
  mkdir -p "$TMP/bin"
  : >"$ZOXIDE"
  : >"$PANES"
  export REPOS="github.com/a/alpha
github.com/a/alpha2
github.com/b/beta
github.com/c/gamma"

  cat >"$TMP/bin/ghq" <<'EOF'
#!/bin/sh
case "$1" in
  root) echo "$ROOT" ;;
  list) printf '%s\n' "$REPOS" ;;
esac
EOF
  cat >"$TMP/bin/zoxide" <<'EOF'
#!/bin/sh
cat "$ZOXIDE"
EOF
  cat >"$TMP/bin/fzf" <<'EOF'
#!/bin/sh
[ -n "${FZF_ABORT:-}" ] && exit 130
head -n1
EOF
  cat >"$TMP/bin/tmux" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$CALLS"
[ "$1" = list-panes ] && cat "$PANES"
exit 0
EOF
  chmod +x "$TMP/bin/"*
  PATH="$TMP/bin:$PATH"
}

teardown() {
  rm -rf "$TMP"
}

@test "zoxide-seen repos come first by score, the rest in ghq order" {
  printf '%6.1f %s\n' 3 "$ROOT/github.com/b/beta" 9 "$ROOT/github.com/c/gamma" >"$ZOXIDE"
  run "$PICK" --list
  [ "$status" -eq 0 ]
  [ "$output" = "github.com/c/gamma
github.com/b/beta
github.com/a/alpha
github.com/a/alpha2" ]
}

@test "subdirectory and worktree visits count toward their repo, not a name-prefix sibling" {
  printf '%6.1f %s\n' \
    5 "$ROOT/github.com/b/beta" \
    4 "$ROOT/github.com/a/alpha/src" \
    4 "$ROOT/github.com/a/alpha/.claude/worktrees/x" \
    1 "$ROOT/github.com/a/alpha2" \
    50 "/elsewhere/github.com/c/gamma" >"$ZOXIDE"
  run "$PICK" --list
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = github.com/a/alpha ]
  [ "${lines[1]}" = github.com/b/beta ]
  [ "${lines[2]}" = github.com/a/alpha2 ]
}

@test "a failing zoxide leaves ghq's order" {
  printf '#!/bin/sh\nexit 1\n' >"$TMP/bin/zoxide"
  run "$PICK" --list
  [ "$status" -eq 0 ]
  [ "$output" = "$REPOS" ]
}

@test "a pick prints the absolute path; an abort prints nothing and fails" {
  run "$PICK"
  [ "$status" -eq 0 ]
  [ "$output" = "$ROOT/github.com/a/alpha" ]
  FZF_ABORT=1 run "$PICK"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "prefix + G goes to the window already inside the repo" {
  printf '%s\n' "@1 $ROOT/github.com/a/alpha2" "@2 $ROOT/github.com/a/alpha/.claude/worktrees/x" >"$PANES"
  run "$WINDOW"
  [ "$status" -eq 0 ]
  grep -qx 'select-window -t @2' "$CALLS"
  ! grep -q new-window "$CALLS"
}

@test "prefix + G opens a window when none is in the repo" {
  printf '%s\n' "@1 $ROOT/github.com/a/alpha2" >"$PANES"
  run "$WINDOW"
  [ "$status" -eq 0 ]
  grep -qx "new-window -c $ROOT/github.com/a/alpha" "$CALLS"
}

@test "prefix + G does nothing when the pick is aborted" {
  FZF_ABORT=1 run "$WINDOW"
  [ "$status" -eq 0 ]
  ! grep -qE 'select-window|new-window' "$CALLS"
}
