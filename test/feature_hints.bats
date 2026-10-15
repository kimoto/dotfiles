#!/usr/bin/env bats

# The feature-hint hooks in .zshrc and the table they read, config/zsh/hints.
# A hint is only worth printing while it is rare and true: rare is the
# once-a-day stamp, true is the key still opening what the hint says.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # .zshrc is sourced whole, and anything in it that runs git must not see
  # the checkout's own config.
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  STATE="$BATS_TEST_TMPDIR/state"
  # .zshrc pins XDG_CONFIG_HOME to ~/.config, so the table is reached the way
  # mklink.sh lays it out: ~/.config is this repo's config/.
  FAKE_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$FAKE_HOME"
  ln -s "$REPO_ROOT/config" "$FAKE_HOME/.config"
}

# Run each argument as a command line through the hooks, the way zsh would:
# preexec with the line as typed, then precmd for the prompt after it.
run_hooks() {
  local lines=""
  local cmd
  for cmd in "$@"; do lines+="_feature_hint_match '$cmd'; _feature_hint;"; done
  run zsh -f -c "
    export HOME='$FAKE_HOME' ZDOTDIR='$REPO_ROOT' XDG_STATE_HOME='$STATE'
    export DOTFILES_NO_SYNC_CHECK=1 DOTFILES_NO_BREW_CHECK=1 DOTFILES_NO_MISE_CHECK=1
    export TMUX=${TMUX_VALUE-/tmp/fake-tmux-socket,1,0}
    source '$REPO_ROOT/.zshrc' >/dev/null 2>&1
    $lines
  "
}

@test "a matching command leaves its hint for the next prompt" {
  run_hooks "git diff --stat"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hint: prefix + v → hunk diff --watch beside this pane, live as files change"* ]]
}

@test "the same hint stays quiet for the rest of the day" {
  run_hooks "git diff" "git diff HEAD~1"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'hint:' <<<"$output")" -eq 1 ]
}

@test "a command no row matches prints nothing" {
  run_hooks "git status" "ls"
  [ "$status" -eq 0 ]
  [[ "$output" != *"hint:"* ]]
}

@test "outside tmux there is no key to press, so no hint" {
  TMUX_VALUE="" run_hooks "git diff"
  [ "$status" -eq 0 ]
  [[ "$output" != *"hint:"* ]]
}

@test "every hinted key opens what its hint says" {
  local sock="feature_hints_$$" key pattern expect rows bound
  tmux -L "$sock" -f "$REPO_ROOT/.tmux.conf" new-session -d -s HINTS
  rows="$(grep -v '^#' "$REPO_ROOT/config/zsh/hints")"
  [ -n "$rows" ]
  while IFS=$'\t' read -r pattern key expect _; do
    bound="$(tmux -L "$sock" list-keys -T prefix -- "$key" 2>/dev/null || true)"
    if ! grep -Eq -- "$expect" <<<"$bound"; then
      tmux -L "$sock" kill-server
      echo "hint for '$pattern' names prefix + $key, but that is not /$expect/ (bound: ${bound:-nothing})" >&2
      return 1
    fi
  done <<<"$rows"
  tmux -L "$sock" kill-server
}
