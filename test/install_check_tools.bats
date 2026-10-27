#!/usr/bin/env bats

# bin/install_check_tools.sh under a stub mise and a stub-only PATH, so no test
# downloads anything or depends on what the host has installed.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/sysbin" "$TMP/out" "$TMP/installs/good"
  printf '#!/bin/sh\n' >"$TMP/installs/good/good-tool"
  chmod +x "$TMP/installs/good/good-tool"

  # CI runs as a regular user, so the script reaches for sudo to link.
  printf '#!/bin/sh\nexec "$@"\n' >"$TMP/sysbin/sudo"
  chmod +x "$TMP/sysbin/sudo"

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

# An apt-get that records each call, so a test can see where it was told to
# keep the .debs it downloads.
apt_stub() {
  ln -s "$(command -v mkdir)" "$TMP/sysbin/mkdir"
  cat >"$TMP/sysbin/apt-get" <<STUB
#!/bin/bash
echo "\$*" >>"$TMP/apt.log"
STUB
  chmod +x "$TMP/sysbin/apt-get"
}

@test "apt keeps its downloads in CHECK_TOOLS_APT_ARCHIVES when it is set" {
  mise_stub 0
  apt_stub
  run env CHECK_TOOLS_BIN_DIR="$TMP/out" PATH="$TMP/sysbin" \
    CHECK_TOOLS_APT_ARCHIVES="$TMP/debs" "$REPO_ROOT/bin/install_check_tools.sh"
  [ "$status" -eq 0 ]
  grep -q "^install .*-o Dir::Cache::Archives=$TMP/debs " "$TMP/apt.log"
  [ -d "$TMP/debs/partial" ]
}

@test "apt uses its own archive directory when CHECK_TOOLS_APT_ARCHIVES is unset" {
  mise_stub 0
  apt_stub
  run_install
  [ "$status" -eq 0 ]
  grep -q "^install " "$TMP/apt.log"
  ! grep -q "Dir::Cache::Archives" "$TMP/apt.log"
}

# A release signed by a throwaway key, served by a stub curl from $TMP/release.
# Asserts on the download path the stub-mise tests above skip: mise is absent,
# so the script fetches it, checks the signature and the sha256, and installs.
release_fixture() {
  # The script itself only runs on Linux, but lefthook runs this suite on macOS
  # too, which may have neither.
  command -v gpg >/dev/null && command -v sha256sum >/dev/null ||
    skip "needs gpg and sha256sum"
  for real in gpg sha256sum awk grep mktemp rm cut install cp; do
    real_path="$(command -v "$real")" || return 1
    ln -sf "$real_path" "$TMP/sysbin/$real"
  done
  export GNUPGHOME="$TMP/gnupg"
  mkdir -m 700 "$GNUPGHOME"
  gpg --batch --quiet --passphrase '' --quick-gen-key 'test <t@example.invalid>' ed25519 sign never
  FPR="$(gpg --batch --with-colons --list-keys | awk -F: '$1 == "fpr" { print $10; exit }')"
  gpg --batch --armor --export >"$TMP/key.asc"

  mkdir -p "$TMP/release" "$TMP/dest"
  asset="mise-v1.0.0-linux-$(uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/')"
  # The "mise" it installs is the stub: the script runs it right after.
  mise_stub 0
  mv "$TMP/sysbin/mise" "$TMP/release/$asset"
  (cd "$TMP/release" && sha256sum "./$asset") >"$TMP/release/SHASUMS256.txt"
  gpg --batch --yes --clearsign -o "$TMP/release/SHASUMS256.asc" "$TMP/release/SHASUMS256.txt"
  unset GNUPGHOME

  cat >"$TMP/sysbin/curl" <<STUB
#!/bin/bash
# curl -sSfL -o <out> <url>
cp "$TMP/release/\${4##*/}" "\$3"
STUB
  chmod +x "$TMP/sysbin/curl"
}

run_download() {
  run env CHECK_TOOLS_BIN_DIR="$TMP/out" PATH="$TMP/sysbin:$TMP/dest" \
    MISE_VERSION=1.0.0 MISE_INSTALL_DIR="$TMP/dest" \
    MISE_RELEASE_KEY="$TMP/key.asc" MISE_RELEASE_FPR="${1:-$FPR}" \
    "$REPO_ROOT/bin/install_check_tools.sh"
}

@test "a mise whose signed sha256 matches is installed" {
  release_fixture
  run_download
  [ "$status" -eq 0 ]
  [ -x "$TMP/dest/mise" ]
}

@test "a mise changed after signing is refused" {
  release_fixture
  echo tampered >>"$TMP/release/$asset"
  run_download
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not match its signed sha256"* ]]
  [ ! -e "$TMP/dest/mise" ]
}

@test "a list signed by any other key is refused" {
  release_fixture
  run_download 0000000000000000000000000000000000000000
  [ "$status" -ne 0 ]
  [[ "$output" == *"is not signed by"* ]]
  [ ! -e "$TMP/dest/mise" ]
}
