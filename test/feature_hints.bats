#!/usr/bin/env bats

# The feature-hint hooks in .zshrc: inside tmux, a matching command names the
# tmux key that does its job, using that binding's own -N note.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # .zshrc is sourced whole, and anything in it that runs git must not see
  # the checkout's own config.
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  SOCK="feature_hints_$$"
  tmux -L "$SOCK" -f "$REPO_ROOT/.tmux.conf" new-session -d -s HINTS
  TMUX_VALUE="$(tmux -L "$SOCK" display-message -p '#{socket_path}'),0,0"
}

teardown() {
  tmux -L "$SOCK" kill-server 2>/dev/null || true
}

# Run each argument as a command line through the hooks, the way zsh would:
# preexec with the line as typed, then precmd for the prompt after it.
run_hooks() {
  local lines="" cmd
  for cmd in "$@"; do lines+="_feature_hint_match '$cmd'; _feature_hint;"; done
  run zsh -f -c "
    export ZDOTDIR='$REPO_ROOT' DOTFILES_NO_SYNC_CHECK=1 DOTFILES_NO_BREW_CHECK=1 DOTFILES_NO_MISE_CHECK=1
    source '$REPO_ROOT/.zshrc' >/dev/null 2>&1
    export TMUX='$TMUX_VALUE'
    $lines
  "
}

@test "a matching command names its key with the binding's note, once per shell" {
  run_hooks "git diff --stat" "git diff HEAD~1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hint: prefix + v → hunk: live diff of this checkout beside the pane"* ]]
  [ "$(grep -c 'hint:' <<<"$output")" -eq 1 ]
}

@test "outside tmux, or for a command no key does better, nothing prints" {
  TMUX_VALUE="" run_hooks "git diff"
  [[ "$output" != *"hint:"* ]]
  run_hooks "git status"
  [[ "$output" != *"hint:"* ]]
}

@test "every key a hint names carries a note in .tmux.conf" {
  local keys key
  keys="$(sed -n "s/.*_feature_hint_key=\([^ ;]\{1,\}\) ;;.*/\1/p" "$REPO_ROOT/.zshrc")"
  [ -n "$keys" ]
  for key in $keys; do
    tmux -L "$SOCK" list-keys -N -T prefix -- "$key" | grep -q . \
      || { echo "prefix + $key has no -N note" >&2; return 1; }
  done
}
