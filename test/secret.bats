#!/usr/bin/env bats

# Tests for bin/secret.sh. `security` and `bw` are stubs: the Keychain is a
# folder of files, and every argv the stubs see is logged, so a secret on a
# command line shows up there.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/secret.sh"
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/bin" "$TMP/kc"
  export STUB_KC="$TMP/kc" STUB_ARGV="$TMP/argv"
  : >"$STUB_ARGV"
  cat >"$TMP/bin/security" <<'STUB'
#!/bin/bash
echo "security $*" >>"$STUB_ARGV"
[ -n "${STUB_KC_LOCKED:-}" ] && exit 51
op="$1"
if [ "$op" = -i ]; then
  line=$(cat)
  eval "set -- $line"
  op="$1"
fi
shift
svc="" acct="" pw=""
while [ $# -gt 0 ]; do
  case "$1" in
    -s) svc="$2"; shift 2 ;;
    -a) acct="$2"; shift 2 ;;
    -w) if [ $# -ge 2 ]; then pw="$2"; shift 2; else shift; fi ;;
    -T) shift 2 ;;
    *) shift ;;
  esac
done
f="$STUB_KC/$svc--$acct"
case "$op" in
  find-generic-password) [ -f "$f" ] || exit 44; cat "$f"; echo ;;
  delete-generic-password) [ -f "$f" ] || exit 44; rm "$f" ;;
  add-generic-password) [ "${STUB_KC_FAIL:-0}" = 1 ] && exit 0; printf '%s' "$pw" >"$f" ;;
esac
STUB
  # The vault: a name, a tab, the notes. --search matches any name containing it.
  printf '%s\t%s\n' "api key" "s3cr3t-value" "api key old" "stale" "empty" "" \
    "quoted" 'a"b' "backslash" 'a\b' "apostrophe" "a'b" "accent" "x$(printf '\303\251')y" \
    "twin" "1" "twin" "2" >"$TMP/vault"
  export STUB_VAULT="$TMP/vault"
  # `bw list` reads a local cache of the vault; `bw sync` refreshes it from the
  # server copy, vault.server, when a test has put one there.
  cat >"$TMP/bin/bw" <<'STUB'
#!/bin/bash
echo "bw $*" >>"$STUB_ARGV"
[ -n "${BW_SESSION:-}" ] || { echo "Vault is locked." >&2; exit 1; }
[ -z "${STUB_BW_FAIL:-}" ] || { echo "Invalid session." >&2; exit 1; }
if [ "$1" = sync ]; then
  [ ! -f "$STUB_VAULT.server" ] || mv "$STUB_VAULT.server" "$STUB_VAULT"
  exit 0
fi
[ "$1 $2 $3" = "list items --search" ] || exit 1
while IFS=$'\t' read -r name notes; do
  case "$name" in *"$4"*) jq -n --arg n "$name" --arg v "$notes" '{name: $n, notes: $v}' ;; esac
done <"$STUB_VAULT" | jq -s .
STUB
  chmod +x "$TMP/bin/security" "$TMP/bin/bw"
  export PATH="$TMP/bin:$PATH"
  unset BW_SESSION
}

teardown() {
  rm -rf "$TMP"
}

copy() {
  cat "$TMP/kc/dotfiles-secret--$1"
}

@test "a refresh copies the secret into the Keychain and prints nothing on stdout" {
  BW_SESSION=x run --separate-stderr "$SCRIPT" --refresh "api key"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(copy "api key")" = s3cr3t-value ]
}

@test "the secret never appears on a command line" {
  BW_SESSION=x run "$SCRIPT" --refresh "api key"
  [ "$status" -eq 0 ]
  ! grep -q s3cr3t "$STUB_ARGV"
}

@test "the item is matched by its exact name, not by search" {
  BW_SESSION=x run "$SCRIPT" --refresh "api"
  [ "$status" -ne 0 ]
  [[ "$output" == *"0 items"* ]]
  [ ! -e "$TMP/kc/dotfiles-secret--api" ]
}

@test "two items with the same name are refused" {
  BW_SESSION=x run "$SCRIPT" --refresh twin
  [ "$status" -ne 0 ]
  [[ "$output" == *"2 items"* ]]
}

@test "a cached secret is printed without asking Bitwarden" {
  printf 's3cr3t-value' >"$TMP/kc/dotfiles-secret--api key"
  run "$SCRIPT" "api key"
  [ "$status" -eq 0 ]
  [ "$output" = s3cr3t-value ]
  ! grep -q '^bw' "$STUB_ARGV"
}

@test "a missing copy fails with a command that can be pasted, and does not reach for Bitwarden" {
  BW_SESSION=x run "$SCRIPT" "Bob's key"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--refresh Bob\\'s\\ key"* ]]
  ! grep -q '^bw' "$STUB_ARGV"
}

@test "a locked Keychain is named as such, not as a missing copy" {
  STUB_KC_LOCKED=1 run "$SCRIPT" "api key"
  [ "$status" -ne 0 ]
  [[ "$output" == *unlock-keychain* ]]
  [[ "$output" != *"not in the Keychain"* ]]
}

@test "a locked vault fails the refresh and keeps the old copy" {
  printf 'old' >"$TMP/kc/dotfiles-secret--api key"
  run "$SCRIPT" --refresh "api key"
  [ "$status" -ne 0 ]
  [[ "$output" == *BW_SESSION* ]]
  [ "$(copy "api key")" = old ]
}

@test "a stale session fails the refresh and keeps the old copy" {
  printf 'old' >"$TMP/kc/dotfiles-secret--api key"
  STUB_BW_FAIL=1 BW_SESSION=x run "$SCRIPT" --refresh "api key"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid session"* ]]
  [ "$(copy "api key")" = old ]
}

@test "a refresh syncs first, so a key just changed in the vault is not cached at its old value" {
  printf '%s\t%s\n' "api key" "rotated" >"$TMP/vault.server"
  BW_SESSION=x run "$SCRIPT" --refresh "api key"
  [ "$status" -eq 0 ]
  [ "$(copy "api key")" = rotated ]
}

@test "a refresh replaces an older copy" {
  printf 'old' >"$TMP/kc/dotfiles-secret--api key"
  BW_SESSION=x run "$SCRIPT" --refresh "api key"
  [ "$status" -eq 0 ]
  [ "$(copy "api key")" = s3cr3t-value ]
}

@test "empty notes are refused, not cached" {
  BW_SESSION=x run "$SCRIPT" --refresh empty
  [ "$status" -ne 0 ]
  [[ "$output" == *"empty notes"* ]]
  [ ! -e "$TMP/kc/dotfiles-secret--empty" ]
}

@test "a value that security -i cannot carry exactly is refused" {
  for item in quoted backslash apostrophe; do
    BW_SESSION=x run "$SCRIPT" --refresh "$item"
    [ "$status" -ne 0 ]
    [[ "$output" == *"line break"* ]]
    [ ! -e "$TMP/kc/dotfiles-secret--$item" ]
  done
}

@test "a value too long for security -i is refused" {
  printf '%s\t%s\n' "long" "$(printf 'x%.0s' {1..1001})" >>"$TMP/vault"
  BW_SESSION=x run "$SCRIPT" --refresh long
  [ "$status" -ne 0 ]
  [[ "$output" == *"too long"* ]]
}

@test "a value outside printable ASCII is refused, since security -w would print it as hex" {
  BW_SESSION=x run "$SCRIPT" --refresh accent
  [ "$status" -ne 0 ]
  [[ "$output" == *ASCII* ]]
  [ ! -e "$TMP/kc/dotfiles-secret--accent" ]
}

@test "a save that did not land is reported, read back rather than trusted" {
  STUB_KC_FAIL=1 BW_SESSION=x run "$SCRIPT" --refresh "api key"
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not save"* ]]
}

@test "--forget drops the copy, and a missing one is fine" {
  printf 's3cr3t-value' >"$TMP/kc/dotfiles-secret--api key"
  run "$SCRIPT" --forget "api key"
  [ "$status" -eq 0 ]
  [ ! -e "$TMP/kc/dotfiles-secret--api key" ]
  run "$SCRIPT" --forget "api key"
  [ "$status" -eq 0 ]
}

@test "--forget that cannot delete says so" {
  STUB_KC_LOCKED=1 run "$SCRIPT" --forget "api key"
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not delete"* ]]
}

@test "without a Keychain it fails at once, never waiting on Bitwarden" {
  SECRET_SECURITY=no-such-command BW_SESSION=x run "$SCRIPT" "api key"
  [ "$status" -ne 0 ]
  [[ "$output" == *"needs the macOS Keychain"* ]]
  ! grep -q '^bw' "$STUB_ARGV"
}

@test "usage errors" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  run "$SCRIPT" a b
  [ "$status" -ne 0 ]
  run "$SCRIPT" --refresh
  [ "$status" -ne 0 ]
  run "$SCRIPT" --bogus x
  [ "$status" -ne 0 ]
  [[ "$output" == *usage* ]]
}
