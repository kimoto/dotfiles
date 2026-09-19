#!/usr/bin/env bats

# Guards how bin/ scripts launch each other.
#
# bin/mkworld.sh used to run its helpers as `sh "$BASE_DIR/bin/<script>"`. On
# macOS that is harmless — /bin/sh there is bash in POSIX mode — but on Linux
# /bin/sh is dash, and bin/setup_homebrew.sh opens with `set -euo pipefail`.
# dash rejects it ("Illegal option -o pipefail") and, under mkworld's own
# `set -e`, the whole bootstrap died at the Homebrew step: no submodules, no
# tpm plugins, no Claude tmux hooks, no lefthook. Failing on the *first* Linux
# machine to run it, and only there, is exactly the failure mode this repo's
# CI cannot see, so pin it here instead.
#
# The rule: a script's shebang decides its interpreter. Helpers are executed
# directly, which means they must also stay executable.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  cd "$REPO_ROOT"
}

@test "no bin script launches another one through a hard-coded sh/bash" {
  offenders=""
  for f in bin/*.sh; do
    while IFS= read -r hit; do
      offenders="$offenders
  $f: $hit"
    done < <(grep -nE '(^|[[:space:]])(sh|bash)[[:space:]]+"?\$\{?[A-Za-z_][A-Za-z_0-9]*\}?/bin/' "$f" || true)
  done
  [ -z "$offenders" ] || echo "hard-coded interpreter (use the shebang):$offenders"
  [ -z "$offenders" ]
}

@test "every bin script is executable" {
  # Sourced libraries are exempt, and say so in their own header — the same
  # marker that tells a reader not to run them.
  offenders=""
  for f in bin/*.sh; do
    grep -q '\*sourced\*, not executed' "$f" && continue
    [ -x "$f" ] || offenders="$offenders $f"
  done
  [ -z "$offenders" ] || echo "not executable:$offenders"
  [ -z "$offenders" ]
}

@test "every bin script that needs bash says so in its shebang" {
  # `set -o pipefail`, arrays, [[ ]] and $'...' are bash-only; a #!/bin/sh
  # shebang on top of them is the same dash trap one level down.
  # bash's [[ always has a space after it, which is what keeps a POSIX
  # character class ([[:space:]]) from reading as the bash keyword.
  offenders=""
  for f in bin/*.sh; do
    head -1 "$f" | grep -q 'bash' && continue
    if grep -qE '(set .*pipefail|\[\[[[:space:]]|^[[:space:]]*[A-Za-z_][A-Za-z_0-9]*=\()' "$f"; then
      offenders="$offenders $f"
    fi
  done
  [ -z "$offenders" ] || echo "bash syntax under a #!/bin/sh shebang:$offenders"
  [ -z "$offenders" ]
}
