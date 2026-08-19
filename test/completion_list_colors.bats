#!/usr/bin/env bats

# Regression test for the completion `list-colors` style in .zshrc.
#
# LS_COLORS is exported by the vivid-ls-colors plugin, which sheldon loads
# through zsh-defer — i.e. after the first prompt. .zshrc runs long before
# that, so the original `zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}`
# captured an empty value and every completion candidate was listed
# uncoloured, on every machine. The style is now registered with `zstyle -e`,
# which evaluates its body at each lookup, so it sees whatever LS_COLORS holds
# by the time a completion actually runs.
#
# This file covers the style value only — it is a unit test and runs in the
# plain static_checks job. That the candidates are then *drawn* coloured needs
# a real terminal, so it lives with the other interactive e2e tests:
# bin/ci_completion_colors_test.sh.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "list-colors reflects an LS_COLORS exported after .zshrc has loaded" {
  # Mirrors the real timeline: .zshrc first, LS_COLORS second (deferred vivid).
  run zsh -f -c "
    export ZDOTDIR='$REPO_ROOT'
    export DOTFILES_NO_SYNC_CHECK=1
    export DOTFILES_NO_BREW_CHECK=1
    source '$REPO_ROOT/.zshrc' >/dev/null 2>&1
    export LS_COLORS='di=01;34:*.txt=01;35'
    zstyle -a ':completion:*' list-colors _lc
    print -r -- \"n=\$#_lc\"
    print -rl -- \"\$_lc[@]\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"n=2"* ]]
  [[ "$output" == *"di=01;34"* ]]
  [[ "$output" == *"*.txt=01;35"* ]]
}
