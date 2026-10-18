#!/usr/bin/env bats

# Tests for bin/local_layer_report.sh against a throwaway $HOME.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/local_layer_report.sh"
  export HOME="$(mktemp -d)"
}

teardown() {
  rm -rf "$HOME"
}

@test "a fresh machine has none of the local files, and is told where the templates are" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"none present"* ]]
  [[ "$output" == *".zshrc.local"*"absent"* ]]
  [[ "$output" == *"$REPO_ROOT/local.example/"* ]]
}

@test "files this machine has are listed as present, the rest as absent" {
  touch "$HOME/.zshrc.local" "$HOME/.gitconfig.local"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *".gitconfig.local .zshrc.local present"* ]]
  [[ "${lines[1]}" == *".bashrc.local .tmux.conf.local absent"* ]]
}

@test "a machine with every local file reports nothing absent" {
  for f in "$REPO_ROOT"/local.example/.*.local; do touch "$HOME/${f##*/}"; done
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" != *"absent"* ]]
}

@test "every local file the dotfiles source has a template" {
  # The sourcing lines are the source of truth; a new one without a template
  # would leave that layer unlisted again.
  local f
  for f in $(grep -ohE '[.][a-z.]+[.]local\b' "$REPO_ROOT/.zshrc" "$REPO_ROOT/.bashrc" \
      "$REPO_ROOT/.tmux.conf" "$REPO_ROOT/.gitconfig" | sort -u); do
    [ -f "$REPO_ROOT/local.example/$f" ] || { echo "no template for $f" >&2; return 1; }
  done
}
