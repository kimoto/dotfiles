#!/usr/bin/env bats

# bin/install_check_tools.sh under a stub mise and a stub-only PATH, so no test
# downloads anything or depends on what the host has installed.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/sysbin" "$TMP/out" "$TMP/installs/good"
  printf '#!/bin/sh\n' >"$TMP/installs/good/good-tool"
  chmod +x "$TMP/installs/good/good-tool"

  for real in id uname dirname readlink jq ln cat; do
    real_path="$(command -v "$real")" || return 1
    ln -s "$real_path" "$TMP/sysbin/$real"
  done
}

teardown() {
  rm -rf "$TMP"
}

# A mise whose `install` exits $1, with one tool installed and one not.
mise_stub() {
  cat >"$TMP/sysbin/mise" <<STUB
#!/bin/bash
case "\$1" in
  install) exit $1 ;;
  ls) echo '{"aqua:good/tool": [], "aqua:missing/tool": []}' ;;
  bin-paths)
    [ "\$2" = "aqua:good/tool" ] || { echo "not installed" >&2; exit 1; }
    echo "$TMP/installs/good" ;;
esac
STUB
  chmod +x "$TMP/sysbin/mise"
}

run_install() {
  run env CHECK_TOOLS_BIN_DIR="$TMP/out" PATH="$TMP/sysbin" \
    "$REPO_ROOT/bin/install_check_tools.sh"
}

@test "every installed tool is linked onto PATH" {
  mise_stub 0
  run_install
  [ "$status" -eq 0 ]
  [ -L "$TMP/out/good-tool" ]
}

@test "a tool that fails to install still leaves the others on PATH" {
  mise_stub 1
  run_install
  [ "$status" -ne 0 ]
  [ -L "$TMP/out/good-tool" ]
}
