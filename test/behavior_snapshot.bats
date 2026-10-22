#!/usr/bin/env bats

# behavior_snapshot.sh is the evidence a refactor changed nothing, so what
# matters is both directions: a change in what the config does shows up as a
# diff, and a change that only touches comments shows up as none. It also has
# to print the same bytes for the same config twice, or every compare would
# fail on noise.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  command -v zsh >/dev/null || skip "zsh not installed"
  TMP="$(fixture_tmpdir)"
  REPO="$TMP/repo"
  mkdir -p "$REPO/bin" "$REPO/config"
  cp "$REPO_ROOT/bin/behavior_snapshot.sh" "$REPO/bin/"
  cat >"$REPO/.zshrc" <<'EOF'
# say hello
alias hi='echo hi'
setopt autocd
EOF
  cat >"$REPO/.tmux.conf" <<'EOF'
# a user option
set -g @fixture on
EOF
  touch "$REPO/config/.keep"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email t@t.test
  git -C "$REPO" config user.name t
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "feat: init"
}

teardown() {
  rm -rf "$TMP"
}

need_tmux() {
  command -v tmux >/dev/null || skip "tmux not installed"
}

@test "zsh: two loads of the same config print the same bytes" {
  run "$REPO/bin/behavior_snapshot.sh" zsh
  [ "$status" -eq 0 ]
  first="$output"
  run "$REPO/bin/behavior_snapshot.sh" zsh
  [ "$output" = "$first" ]
  [[ "$output" == *"alias hi='echo hi'"* ]]
  [[ "$output" == *$'\nautocd\n'* ]]
}

@test "zsh: paths read as <HOME> and <REPO>, not where they happened to be" {
  echo 'MY_ROOT=${${(%):-%x}:A:h}' >>"$REPO/.zshrc"
  run "$REPO/bin/behavior_snapshot.sh" zsh
  [[ "$output" == *"typeset MY_ROOT=<REPO>"* ]]
  [[ "$output" == *"export HOME=<HOME>"* ]]
  [[ "$output" != *"$TMP"* ]]
}

@test "zsh: sheldon plugins stay out, so no network fetch decides the result" {
  mkdir "$TMP/fakebin"
  printf '#!/bin/sh\necho "alias from_plugin=x"\n' >"$TMP/fakebin/sheldon"
  chmod +x "$TMP/fakebin/sheldon"
  echo 'command -v sheldon >/dev/null && eval "$(sheldon source)"' >>"$REPO/.zshrc"
  PATH="$TMP/fakebin:$PATH" run "$REPO/bin/behavior_snapshot.sh" zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"alias hi="* ]]
  [[ "$output" != *"from_plugin"* ]]
}

@test "tmux: two loads print the same bytes and include the config's options" {
  need_tmux
  run "$REPO/bin/behavior_snapshot.sh" tmux
  [ "$status" -eq 0 ]
  first="$output"
  run "$REPO/bin/behavior_snapshot.sh" tmux
  [ "$output" = "$first" ]
  [[ "$output" == *"@fixture on"* ]]
}

@test "compare: a comment-only change reports no difference" {
  need_tmux
  sed -i.bak 's/# say hello/# greet whoever asks/' "$REPO/.zshrc"
  sed -i.bak 's/# a user option/# set for the test/' "$REPO/.tmux.conf"
  run "$REPO/bin/behavior_snapshot.sh" compare HEAD
  [ "$status" -eq 0 ]
  [[ "$output" == *"zsh: no difference from HEAD"* ]]
  [[ "$output" == *"tmux: no difference from HEAD"* ]]
}

@test "compare: a changed alias and a changed tmux option fail with the diff" {
  need_tmux
  sed -i.bak "s/echo hi/echo hello/" "$REPO/.zshrc"
  sed -i.bak "s/@fixture on/@fixture off/" "$REPO/.tmux.conf"
  run "$REPO/bin/behavior_snapshot.sh" compare HEAD
  [ "$status" -eq 1 ]
  [[ "$output" == *"-alias hi='echo hi'"* ]]
  [[ "$output" == *"+alias hi='echo hello'"* ]]
  [[ "$output" == *"+@fixture off"* ]]
}

@test "compare: a change under config/ shows, not the real ~/.config" {
  need_tmux
  echo 'source "$HOME/.config/extra.zsh"' >>"$REPO/.zshrc"
  echo "alias extra='one'" >"$REPO/config/extra.zsh"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "feat: extra"
  echo "alias extra='two'" >"$REPO/config/extra.zsh"
  run "$REPO/bin/behavior_snapshot.sh" compare HEAD
  [ "$status" -eq 1 ]
  [[ "$output" == *"+alias extra=two"* ]]
}

@test "compare: leaves no worktree behind" {
  need_tmux
  run "$REPO/bin/behavior_snapshot.sh" compare HEAD
  [ "$status" -eq 0 ]
  run git -C "$REPO" worktree list
  [ "${#lines[@]}" -eq 1 ]
}

@test "rejects an unknown mode" {
  run "$REPO/bin/behavior_snapshot.sh" bash
  [ "$status" -eq 2 ]
  [[ "$output" == usage:* ]]
}
