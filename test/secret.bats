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
f="$STUB_KC/$svc--${acct//\//%}"
case "$op" in
  find-generic-password) [ -f "$f" ] || exit 44; cat "$f"; echo ;;
  delete-generic-password) [ -f "$f" ] || exit 44; rm "$f" ;;
  add-generic-password) [ "${STUB_KC_FAIL:-0}" = 1 ] && exit 0; printf '%s' "$pw" >"$f" ;;
esac
STUB
  # The vault: a name, a tab, the notes. --search matches any name containing it.
  # Notes written as pw=VALUE stand for an item whose password is VALUE.
  printf '%s\t%s\n' "api key" "s3cr3t-value" "api key old" "stale" "empty" "" \
    "quoted" 'a"b' "backslash" 'a\b' "apostrophe" "a'b" "accent" "x$(printf '\303\251')y" \
    "twin" "1" "twin" "2" "token" "pw=t0ken" "doubled" "both=n" >"$TMP/vault"
  export STUB_VAULT="$TMP/vault"
  # `bw list` reads a local cache of the vault; `bw sync` refreshes it from the
  # server copy, vault.server, when a test has put one there. An item's id is
  # its line number. create and edit log the item they got to written.json;
  # STUB_BW_DROP makes them report success and keep nothing.
  cat >"$TMP/bin/bw" <<'STUB'
#!/bin/bash
echo "bw $*" >>"$STUB_ARGV"
[ "$1" = encode ] && exec base64
[ -n "${BW_SESSION:-}" ] || { echo "Vault is locked." >&2; exit 1; }
[ -z "${STUB_BW_FAIL:-}" ] || { echo "Invalid session." >&2; exit 1; }
item_json() {
  "$REAL_JQ" -n --argjson i "$1" --arg n "$2" --arg v "$3" '{id: ($i | tostring), name: $n} +
    if ($v | startswith("pw=")) then {notes: null, login: {password: ($v | ltrimstr("pw="))}}
    elif ($v | startswith("both=")) then {notes: ($v | ltrimstr("both=")), login: {password: "p"}}
    else {notes: $v} end'
}
case "$1 $2" in
  "sync --nointeraction")
    [ ! -f "$STUB_VAULT.server" ] || mv "$STUB_VAULT.server" "$STUB_VAULT" ;;
  "list items")
    i=0
    while IFS=$'\t' read -r name notes; do
      i=$((i + 1))
      case "$name" in *"$4"*) item_json "$i" "$name" "$notes" ;; esac
    done <"$STUB_VAULT" | "$REAL_JQ" -s . ;;
  "get template")
    echo '{"type":1,"name":"","notes":null,"folderId":null,"login":{"username":null},"secureNote":null}' ;;
  "get item")
    IFS=$'\t' read -r name notes < <(sed -n "${3}p" "$STUB_VAULT")
    item_json "$3" "$name" "$notes" ;;
  "create item" | "edit item")
    base64 -d >"$TMP_DIR/written.json"
    [ -z "${STUB_BW_DROP:-}" ] || exit 0
    line=$("$REAL_JQ" -r \
      '[.name, if (.login.password // "") != "" then "pw=" + .login.password else .notes end] | @tsv' \
      "$TMP_DIR/written.json")
    if [ "$1" = create ]; then
      printf '%s\n' "$line" >>"$STUB_VAULT"
    else
      awk -v n="$3" -v l="$line" 'NR == n { print l; next } { print }' "$STUB_VAULT" >"$STUB_VAULT.new"
      mv "$STUB_VAULT.new" "$STUB_VAULT"
    fi ;;
  *) exit 1 ;;
esac
STUB
  # jq is real, behind a stub that logs its argv too.
  export REAL_JQ="$(command -v jq)"
  printf '#!/bin/bash\necho "jq $*" >>"$STUB_ARGV"\nexec %s "$@"\n' "$(command -v jq)" >"$TMP/bin/jq"
  # The clipboard: paste prints clip, copy writes it.
  printf '#!/bin/bash\ncat "$TMP_DIR/clip"\n' >"$TMP/bin/paste"
  printf '#!/bin/bash\ncat >"$TMP_DIR/clip"\n' >"$TMP/bin/copy"
  export TMP_DIR="$TMP" SECRET_PASTE=paste SECRET_COPY=copy
  chmod +x "$TMP/bin/security" "$TMP/bin/bw" "$TMP/bin/jq" "$TMP/bin/paste" "$TMP/bin/copy"
  export PATH="$TMP/bin:$PATH"
  unset BW_SESSION
}

teardown() {
  rm -rf "$TMP"
}

copy() {
  cat "$TMP/kc/dotfiles-secret--${1//\//%}"
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
  run ! grep -q s3cr3t "$STUB_ARGV"
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
  run ! grep -q '^bw' "$STUB_ARGV"
}

@test "a missing copy fails with a command that can be pasted, and does not reach for Bitwarden" {
  BW_SESSION=x run "$SCRIPT" "Bob's key"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--refresh Bob\\'s\\ key"* ]]
  run ! grep -q '^bw' "$STUB_ARGV"
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

@test "an item with neither a password nor notes is refused, not cached" {
  BW_SESSION=x run "$SCRIPT" --refresh empty
  [ "$status" -ne 0 ]
  [[ "$output" == *"neither a password nor notes"* ]]
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
  run ! grep -q '^bw' "$STUB_ARGV"
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

# The value --set reads on stdin, from a file: `run` in a pipeline would run in
# a subshell and lose $status.
new_value() {
  printf '%s' "$1" >"$TMP/in"
}

@test "--set makes a secure note when there is none, and caches it" {
  new_value n3w-key
  BW_SESSION=x run --separate-stderr "$SCRIPT" --set "env/NEW_KEY" - <"$TMP/in"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"stored: env/NEW_KEY"* ]]
  [ "$(jq -r '[.type, .name, .notes] | @tsv' "$TMP/written.json")" = "$(printf '2\tenv/NEW_KEY\tn3w-key')" ]
  [ "$(copy "env/NEW_KEY")" = n3w-key ]
}

@test "--set replaces the notes of the one item with that name, and leaves the rest" {
  printf 'old' >"$TMP/kc/dotfiles-secret--api key"
  new_value rotated
  BW_SESSION=x run "$SCRIPT" --set "api key" - <"$TMP/in"
  [ "$status" -eq 0 ]
  grep -qx "$(printf 'api key\trotated')" "$TMP/vault"
  grep -qx "$(printf 'api key old\tstale')" "$TMP/vault"
  [ "$(copy "api key")" = rotated ]
}

@test "--set never puts the new value on a command line" {
  new_value n3w-key
  BW_SESSION=x run "$SCRIPT" --set "env/NEW_KEY" - <"$TMP/in"
  [ "$status" -eq 0 ]
  new_value rotated
  BW_SESSION=x run "$SCRIPT" --set "api key" - <"$TMP/in"
  [ "$status" -eq 0 ]
  grep -q '^jq ' "$STUB_ARGV"
  run ! grep -qe n3w-key -e rotated "$STUB_ARGV"
}

@test "--set reads the clipboard by default, trims it, then clears it" {
  printf '  n3w-key \n' >"$TMP/clip"
  BW_SESSION=x run "$SCRIPT" --set "env/NEW_KEY"
  [ "$status" -eq 0 ]
  [ "$(copy "env/NEW_KEY")" = n3w-key ]
  [ ! -s "$TMP/clip" ]
}

@test "--set refuses a value the Keychain cannot carry before writing Bitwarden" {
  new_value 'a"b'
  BW_SESSION=x run "$SCRIPT" --set "api key" - <"$TMP/in"
  [ "$status" -ne 0 ]
  [[ "$output" == *"has a quote"* ]]
  run ! grep -qe '^bw create' -e '^bw edit' "$STUB_ARGV"
  grep -qx "$(printf 'api key\ts3cr3t-value')" "$TMP/vault"
}

@test "--set with a locked Keychain stops before writing Bitwarden" {
  new_value rotated
  STUB_KC_LOCKED=1 BW_SESSION=x run "$SCRIPT" --set "api key" - <"$TMP/in"
  [ "$status" -ne 0 ]
  [[ "$output" == *unlock-keychain* ]]
  run ! grep -q '^bw' "$STUB_ARGV"
}

@test "--set that fails after writing Bitwarden says so, and clears the clipboard" {
  printf 'rotated' >"$TMP/clip"
  STUB_KC_FAIL=1 BW_SESSION=x run "$SCRIPT" --set "api key"
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not save"* ]]
  [[ "$output" == *"Bitwarden already holds"*"--refresh api\\ key"* ]]
  [ ! -s "$TMP/clip" ]
}

@test "--set says when the clipboard cannot be read" {
  printf '#!/bin/bash\nexit 1\n' >"$TMP/bin/paste"
  BW_SESSION=x run "$SCRIPT" --set "api key"
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not read the clipboard"* ]]
}

@test "--set refuses an empty value" {
  printf ' \n' >"$TMP/clip"
  BW_SESSION=x run "$SCRIPT" --set "api key"
  [ "$status" -ne 0 ]
  [[ "$output" == *empty* ]]
  run ! grep -q '^bw' "$STUB_ARGV"
}

@test "--set refuses two items with the same name" {
  new_value x
  BW_SESSION=x run "$SCRIPT" --set twin - <"$TMP/in"
  [ "$status" -ne 0 ]
  [[ "$output" == *"2 items"* ]]
  run ! grep -qe '^bw create' -e '^bw edit' "$STUB_ARGV"
}

@test "--set that Bitwarden did not keep is reported, and the old copy stays" {
  printf 'old' >"$TMP/kc/dotfiles-secret--api key"
  new_value rotated
  STUB_BW_DROP=1 BW_SESSION=x run "$SCRIPT" --set "api key" - <"$TMP/in"
  [ "$status" -ne 0 ]
  [[ "$output" == *"did not keep"* ]]
  [ "$(copy "api key")" = old ]
}

@test "--set with a locked vault writes nothing and keeps the clipboard" {
  printf 'n3w-key' >"$TMP/clip"
  run "$SCRIPT" --set "api key"
  [ "$status" -ne 0 ]
  [[ "$output" == *BW_SESSION* ]]
  [ "$(cat "$TMP/clip")" = n3w-key ]
  [ ! -e "$TMP/kc/dotfiles-secret--api key" ]
}

@test "--set usage errors" {
  run "$SCRIPT" --set
  [ "$status" -ne 0 ]
  run "$SCRIPT" --set "api key" value
  [ "$status" -ne 0 ]
  [[ "$output" == *usage* ]]
  run ! grep -q '^bw' "$STUB_ARGV"
}

@test "an item whose value is in the password field is read from there" {
  BW_SESSION=x run "$SCRIPT" --refresh token
  [ "$status" -eq 0 ]
  [ "$(copy token)" = t0ken ]
}

@test "an item with both a password and notes is refused" {
  BW_SESSION=x run "$SCRIPT" --refresh doubled
  [ "$status" -ne 0 ]
  [[ "$output" == *"both a password and notes"* ]]
  [ ! -e "$TMP/kc/dotfiles-secret--doubled" ]
}

@test "--set replaces the password of an item that keeps its value there" {
  new_value n3w
  BW_SESSION=x run "$SCRIPT" --set token - <"$TMP/in"
  [ "$status" -eq 0 ]
  grep -qx "$(printf 'token\tpw=n3w')" "$TMP/vault"
  [ "$(copy token)" = n3w ]
}

@test "--set refuses an item with both a password and notes before writing it" {
  new_value n3w
  BW_SESSION=x run "$SCRIPT" --set doubled - <"$TMP/in"
  [ "$status" -ne 0 ]
  [[ "$output" == *"both a password and notes"* ]]
  grep -qx "$(printf 'doubled\tboth=n')" "$TMP/vault"
  run ! grep -q '^bw edit' "$STUB_ARGV"
}
