#!/usr/bin/env bats

# mise is stubbed, or the answer would depend on what this machine has
# installed. The script prints the previous run's cache, so a case that wants
# the warning runs twice.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/mise_missing_check.sh"
  TMP="$(mktemp -d)"
  export XDG_CACHE_HOME="$TMP/cache"
  CACHE="$XDG_CACHE_HOME/dotfiles"
  STUB_DIR="$TMP/bin"
  mkdir -p "$STUB_DIR"
  PATH="$STUB_DIR:$PATH"
}

teardown() {
  rm -rf "$TMP"
}

# $1 is what `--missing` prints. Bare `ls` answers with an installed tool, so
# dropping the flag is caught here and not on a machine that then always warns.
stub_mise() {
  cat >"$STUB_DIR/mise" <<EOF
#!/bin/bash
case " \$* " in
  *" --missing "*) printf '%s' "$1" ;;
  *)               printf 'go  1.27.1  ~/.config/mise/config.toml  latest\n' ;;
esac
EOF
  chmod +x "$STUB_DIR/mise"
}

wait_for() {
  for _ in $(seq 1 50); do
    eval "$1" && return 0
    sleep 0.1
  done
  echo "timed out waiting for: $1" >&2
  return 1
}

@test "warns once the background run has seen missing tools" {
  stub_mise 'go    1.27.1 (missing)  ~/.config/mise/config.toml  latest
node  26.8.2 (missing)  ~/.config/mise/config.toml  latest'

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]                      # first run has nothing cached yet
  wait_for '[ -s "$CACHE/mise_missing" ]'

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[mise]"* ]]
  [[ "$output" == *"2 tool"* ]]
  [[ "$output" == *"mise install"* ]]
}

@test "stays silent when nothing is missing" {
  stub_mise ''
  run "$SCRIPT"
  wait_for '[ -f "$CACHE/mise_missing" ]'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "installing the tools clears the warning on the next shell" {
  stub_mise 'go 1.27.1 (missing) config latest'
  run "$SCRIPT"; wait_for '[ -s "$CACHE/mise_missing" ]'
  run "$SCRIPT"; [[ "$output" == *"[mise]"* ]]

  stub_mise ''
  run "$SCRIPT"; wait_for '[ ! -s "$CACHE/mise_missing" ]'
  run "$SCRIPT"
  [ -z "$output" ]
}

@test "a mise too old for --missing is silent, not noisy" {
  # Exits non-zero on stderr, like an unknown flag.
  cat >"$STUB_DIR/mise" <<'EOF'
#!/bin/bash
echo "error: unexpected argument '--missing'" >&2
exit 1
EOF
  chmod +x "$STUB_DIR/mise"

  run "$SCRIPT"
  wait_for '[ -f "$CACHE/mise_missing" ]'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no mise on PATH is silent and spawns nothing" {
  # Set on the run only: clobbering PATH takes rm away from teardown too.
  run env PATH="$STUB_DIR:/usr/bin:/bin" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  sleep 1
  [ ! -f "$CACHE/mise_missing" ]
}

@test "DOTFILES_NO_MISE_CHECK short-circuits with no output" {
  stub_mise 'go 1.27.1 (missing) config latest'
  DOTFILES_NO_MISE_CHECK=1 run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  sleep 1
  [ ! -f "$CACHE/mise_missing" ]
}
