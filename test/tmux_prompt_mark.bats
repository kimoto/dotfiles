#!/usr/bin/env bats

# Regression test for the tmux OSC 133;A prompt-mark hook in .zshrc.
#
# _tmux_prompt_mark runs as a precmd hook so tmux can track prompt positions
# (next-prompt/previous-prompt in copy mode). It used to unconditionally
# prepend the marker to $PROMPT every time, but $PROMPT is a persistent shell
# variable (starship sets it once, to a string containing a `$(...)` command
# substitution that zsh re-evaluates at render time) — nothing resets it
# between precmd calls. Without a guard, every single prompt draw in a
# long-lived tmux session added another marker, so $PROMPT — and the escape
# bytes sent to the terminal on every render — grew without bound.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "_tmux_prompt_mark does not grow PROMPT across repeated precmd cycles" {
  run zsh -f -c "
    export ZDOTDIR='$REPO_ROOT'
    export DOTFILES_NO_SYNC_CHECK=1
    export DOTFILES_NO_BREW_CHECK=1
    export TMUX=/tmp/fake-tmux-socket,1,0
    source '$REPO_ROOT/.zshrc' >/dev/null 2>&1
    for i in 1 2 3 4 5; do
      _tmux_prompt_mark
      print -r -- \${#PROMPT}
    done
  "
  [ "$status" -eq 0 ]
  # lines[0] is the first call (establishes the marker, expected to grow once);
  # every call after that must be a no-op on length.
  [ "${lines[1]}" -eq "${lines[2]}" ]
  [ "${lines[2]}" -eq "${lines[3]}" ]
  [ "${lines[3]}" -eq "${lines[4]}" ]
}
