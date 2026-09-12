#!/usr/bin/env bats

# _evalcache pins a command's output in a file, so an init that prints an
# absolute PATH takes the PATH away from every later shell.
#
# Runs each init rather than reading the toml: the output changes with the
# tool's version.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TOML="$REPO_ROOT/config/sheldon/plugins.toml"
  if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  fi
}

# Only the `inline =` lines: a comment saying _evalcache is prose, not a command.
cached_inits() {
  grep -E "^[[:space:]]*inline[[:space:]]*=" "$TOML" \
    | grep -oE "_evalcache [a-z_][a-zA-Z0-9_ .-]*" \
    | sed -E 's/^_evalcache //; s/ *$//' \
    | sort -u
}

@test "plugins.toml still has cached inits to check" {
  run cached_inits
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "no cached init prints a PATH that drops the shell's own" {
  local failures=""
  while read -r cmd; do
    [ -n "$cmd" ] || continue
    # .zshrc's own functions and absent tools are not runnable here.
    command -v "${cmd%% *}" >/dev/null 2>&1 || continue

    local out
    out="$(eval "$cmd" 2>/dev/null)" || continue

    # An assignment that never mentions $PATH replaces it.
    local assigns keeps
    assigns="$(printf '%s\n' "$out" | grep -cE '^[[:space:]]*(export )?PATH=' || true)"
    [ "${assigns:-0}" -gt 0 ] || continue
    keeps="$(printf '%s\n' "$out" | grep -E '^[[:space:]]*(export )?PATH=' | grep -cE '\$PATH|\$\{PATH' || true)"

    if [ "${keeps:-0}" -lt "${assigns:-0}" ]; then
      failures="$failures$cmd "
    fi
  done < <(cached_inits)

  [ -z "$failures" ] || {
    echo "these cached inits replace PATH instead of extending it: $failures" >&2
    false
  }
}
