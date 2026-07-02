#!/usr/bin/env bats

# Guards the shared e2e pane conventions in bin/tmux_e2e_helpers.sh.
# zsh_pane_cmd is the single source of truth for how the interactive-zsh e2e
# tests spawn their pane (CI cleared, sync/brew startup checks silenced, TERM
# pinned). These tests pin down every flag it must carry, and — like the
# mklink/rmworld sync test — enforce that no e2e test hand-builds that env
# string again: a hand-built copy is exactly how DOTFILES_NO_BREW_CHECK got
# forgotten in three tests at once (PR #83, CI run 1).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/tmux_e2e_helpers.sh"
}

@test "zsh_pane_cmd carries every CI pane convention" {
  REPO=/repo ZSH_BIN=/bin/zsh
  run zsh_pane_cmd
  [ "$status" -eq 0 ]
  [[ "$output" == "env CI= "* ]]
  [[ "$output" == *"ZDOTDIR='/repo'"* ]]
  [[ "$output" == *"DOTFILES_NO_SYNC_CHECK=1"* ]]
  [[ "$output" == *"DOTFILES_NO_BREW_CHECK=1"* ]]
  [[ "$output" == *"TERM=xterm-256color"* ]]
  [[ "$output" == *"'/bin/zsh' -i" ]]
}

@test "zsh_pane_cmd places extra env assignments before zsh" {
  REPO=/repo ZSH_BIN=/bin/zsh
  run zsh_pane_cmd "PATH='/stub:/usr/bin'"
  [ "$status" -eq 0 ]
  [[ "$output" == *" PATH='/stub:/usr/bin' '/bin/zsh' -i" ]]
}

@test "zsh_pane_cmd dies when REPO / ZSH_BIN are not set" {
  unset REPO ZSH_BIN
  run zsh_pane_cmd
  [ "$status" -ne 0 ]
  [[ "$output" == *"zsh_pane_cmd needs REPO and ZSH_BIN"* ]]
}

@test "every e2e test that spawns an interactive zsh pane uses zsh_pane_cmd" {
  local f
  for f in "$REPO_ROOT"/bin/ci_*_test.sh; do
    grep -q 'ZSH_BIN' "$f" || continue       # doesn't launch zsh
    grep -q 'new-session' "$f" || continue   # doesn't spawn a pane
    if ! grep -q 'zsh_pane_cmd' "$f"; then
      echo "$f spawns a zsh pane without zsh_pane_cmd" >&2
      return 1
    fi
    if grep -qE 'new-session.*env CI=' "$f"; then
      echo "$f hand-builds the pane env instead of using zsh_pane_cmd" >&2
      return 1
    fi
  done
}
