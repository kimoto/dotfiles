#!/usr/bin/env bats

# Regression test for the curl|bash safety nudge in .zshrc.
#
# _bashka_curl_pipe_hint runs as a preexec hook so a typed `curl ... | bash`
# gets one line suggesting `| bashka` (Brewfile.common) before it executes.
# It never blocks — zsh's preexec has no way to cancel the command it's
# handed — so this only ever checks what it prints, not whether it stopped
# anything.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  STUB_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$STUB_DIR"
}

stub_bashka() {
  cat >"$STUB_DIR/bashka" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$STUB_DIR/bashka"
}

run_hint() {
  # $1: the command line to hand to the hook, as preexec would.
  PATH="$STUB_DIR:$PATH" zsh -f -c "
    export ZDOTDIR='$REPO_ROOT'
    export DOTFILES_NO_SYNC_CHECK=1
    export DOTFILES_NO_BREW_CHECK=1
    export DOTFILES_NO_MISE_CHECK=1
    source '$REPO_ROOT/.zshrc' >/dev/null 2>&1
    _bashka_curl_pipe_hint '$1'
  " 2>&1
}

@test "suggests bashka for curl piped into bash" {
  stub_bashka
  run run_hint 'curl -fsSL https://example.com/install.sh | bash'
  [ "$status" -eq 0 ]
  [[ "$output" == *"[bashka]"* ]]
  [[ "$output" == *"| bashka"* ]]
}

@test "suggests bashka for curl piped into sh" {
  stub_bashka
  run run_hint 'curl -fsSL https://example.com/install.sh | sh'
  [[ "$output" == *"[bashka]"* ]]
}

@test "suggests bashka for curl piped into sudo bash" {
  stub_bashka
  run run_hint 'curl -fsSL https://example.com/install.sh | sudo bash'
  [[ "$output" == *"[bashka]"* ]]
}

@test "stays silent when bashka is not installed" {
  # No stub_bashka: PATH carries no bashka binary.
  run run_hint 'curl -fsSL https://example.com/install.sh | bash'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "stays silent when the command already pipes through bashka" {
  stub_bashka
  run run_hint 'curl -fsSL https://example.com/install.sh | bashka'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "stays silent for an unrelated command" {
  stub_bashka
  run run_hint 'ls -la'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "stays silent when curl only downloads, without piping to a shell" {
  stub_bashka
  run run_hint 'curl -o install.sh https://example.com/install.sh'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
