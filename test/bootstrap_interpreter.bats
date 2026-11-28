#!/usr/bin/env bats

# Guards how the repo's scripts (bin/, ci/, test/e2e/) launch each other.
#
# A helper launched as `sh "$BASE_DIR/bin/<script>"` runs fine on macOS, where
# /bin/sh is bash in POSIX mode, but on Linux /bin/sh is dash, which rejects
# `set -euo pipefail` ("Illegal option -o pipefail"). Under mkworld's own
# `set -e` the whole bootstrap then dies at that step, and only on the first
# Linux machine to run it: a failure this repo's CI cannot see, so it is
# pinned here instead.
#
# The rule: a script's shebang decides its interpreter. Helpers are executed
# directly, which means they must also stay executable.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  cd "$REPO_ROOT"
}

@test "no bin script launches another one through a hard-coded sh/bash" {
  offenders=""
  for f in bin/*.sh ci/*.sh test/e2e/*.sh; do
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
  for f in bin/*.sh ci/*.sh test/e2e/*.sh; do
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
  for f in bin/*.sh ci/*.sh test/e2e/*.sh; do
    head -1 "$f" | grep -q 'bash' && continue
    if grep -qE '(set .*pipefail|\[\[[[:space:]]|^[[:space:]]*[A-Za-z_][A-Za-z_0-9]*=\()' "$f"; then
      offenders="$offenders $f"
    fi
  done
  [ -z "$offenders" ] || echo "bash syntax under a #!/bin/sh shebang:$offenders"
  [ -z "$offenders" ]
}
