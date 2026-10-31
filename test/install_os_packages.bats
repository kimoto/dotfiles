#!/usr/bin/env bats

# bin/install_os_packages.sh asks apt for exactly the packages dpkg reports
# missing, and does nothing where it cannot become root.
#
# PATH holds only stubs: dpkg-query answers from $INSTALLED, apt-get and sudo
# log their argv, and id says whether we are root.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(mktemp -d)"
  STUB="$TMP/stub"
  mkdir -p "$STUB"
  LOG="$TMP/log"
  : >"$LOG"

  cat >"$STUB/dpkg-query" <<'EOF'
#!/bin/bash
pkg="${!#}"
case " $INSTALLED " in *" $pkg "*) printf 'ii ' ;; *) exit 1 ;; esac
EOF
  cat >"$STUB/apt-get" <<EOF
#!/bin/bash
echo "apt-get \$*" >>"$LOG"
EOF
  cat >"$STUB/sudo" <<EOF
#!/bin/bash
echo "sudo \$1" >>"$LOG"
shift
exec "\$@"
EOF
  cat >"$STUB/id" <<'EOF'
#!/bin/bash
echo "${FAKE_UID:-1000}"
EOF
  chmod +x "$STUB"/*
}

teardown() {
  rm -rf "$TMP"
}

run_script() {
  run env PATH="$STUB" INSTALLED="$INSTALLED" FAKE_UID="${FAKE_UID:-1000}" \
    "$REPO_ROOT/bin/install_os_packages.sh"
}

@test "nothing missing: apt is not called" {
  INSTALLED="git zsh curl libatomic1"
  run_script
  [ "$status" -eq 0 ]
  [ ! -s "$LOG" ]
}

@test "installs only what dpkg reports missing, through sudo" {
  INSTALLED="git curl"
  run_script
  [ "$status" -eq 0 ]
  grep -qx "sudo DEBIAN_FRONTEND=noninteractive" "$LOG"
  grep -qx "apt-get install -y --no-install-recommends zsh libatomic1" "$LOG"
}

@test "as root, apt is called without sudo" {
  INSTALLED="git zsh curl"
  FAKE_UID=0
  run_script
  [ "$status" -eq 0 ]
  ! grep -q '^sudo' "$LOG"
  grep -qx "apt-get install -y --no-install-recommends libatomic1" "$LOG"
}

@test "no sudo and not root: names the packages and installs nothing" {
  INSTALLED="git"
  rm "$STUB/sudo"
  run_script
  [ "$status" -eq 0 ]
  [[ "$output" == *"zsh curl libatomic1"* ]]
  [ ! -s "$LOG" ]
}
