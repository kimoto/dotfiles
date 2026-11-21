#!/usr/bin/env bats

# Behavioural tests for bin/tidy_to_drive.sh. `rclone` is a stub that maps
# the remote onto a temp directory and can be told to fail an upload or hand
# back different bytes, so the one property that matters (no local file goes
# unless the downloaded copy matches) is tested against a good and a lying
# remote. The classifier and `trash` are stubs too.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(mktemp -d)"
  SCRIPT="$REPO_ROOT/bin/tidy_to_drive.sh"
  export DESKTOP="$TMP/Desktop"
  export TIDY_SOURCE_DIRS="$DESKTOP"
  export REMOTE_DIR="$TMP/remote"
  export TRASH_DIR="$TMP/Trash"
  export TMPDIR="$TMP"
  export TIDY_STATE_DIR="$TMP/state"
  export MIN_AGE_MINUTES=0
  mkdir -p "$DESKTOP" "$REMOTE_DIR" "$TRASH_DIR"

  STUB="$TMP/stubbin"
  mkdir -p "$STUB"
  # rclone: "gdrive-paperwork:<path>" is $REMOTE_DIR/<path>.
  cat >"$STUB/rclone" <<'STUBEOF'
#!/bin/bash
if [ "$1" = lsf ]; then
  [ -e "$REMOTE_DIR/${2#gdrive-paperwork:}" ] && basename "$2"
  exit 0
fi
[ "$1" = copyto ] || exit 2
shift
ignore=0
[ "$1" = --ignore-existing ] && { ignore=1; shift; }
[ "${STUB_READ_STDIN:-0}" = 1 ] && cat >/dev/null
src="$1" dst="$2"
case "$dst" in
  gdrive-paperwork:*)
    [ "${STUB_UPLOAD_FAIL:-0}" = 1 ] && exit 1
    out="$REMOTE_DIR/${dst#gdrive-paperwork:}"
    [ "$ignore" = 1 ] && [ -e "$out" ] && exit 0
    mkdir -p "$(dirname "$out")"
    cp "$src" "$out" ;;
  *)
    cp "$REMOTE_DIR/${src#gdrive-paperwork:}" "$dst"
    [ "${STUB_CORRUPT:-0}" = 1 ] && printf x >>"$dst"
    exit 0 ;;
esac
STUBEOF
  cat >"$STUB/trash" <<'STUBEOF'
#!/bin/bash
mv "$1" "$TRASH_DIR/"
STUBEOF
  # The classifier answers from the file's own text: "junk", "unsure", or a
  # "keep<TAB>folder<TAB>name" line written into the file by the test.
  cat >"$STUB/classify" <<'STUBEOF'
#!/bin/bash
[ "${STUB_CLASSIFY_FAIL:-0}" = 1 ] && exit 1
echo "$1" >>"$TMPDIR/classified"
head -n 1 "$1"
STUBEOF
  chmod +x "$STUB/rclone" "$STUB/trash" "$STUB/classify"
  export TIDY_CLASSIFIER="$STUB/classify"
  PATH="$STUB:$PATH"
}

keep_line() {
  printf 'keep\t%s\t%s\n' "$1" "$2"
}

teardown() {
  rm -rf "$TMP"
}

@test "a keeper is filed under its name and deleted once the copy comes back identical" {
  keep_line 2026/2026-11_health-insurance-dependents withholding_2025_taro.pdf >"$DESKTOP/scan.pdf"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$DESKTOP/scan.pdf" ]
  cmp <(keep_line 2026/2026-11_health-insurance-dependents withholding_2025_taro.pdf) \
    "$REMOTE_DIR/2026/2026-11_health-insurance-dependents/withholding_2025_taro.pdf"
}

@test "junk goes to the Trash and never to Drive" {
  echo junk >"$DESKTOP/Screenshot 1.png"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -e "$TRASH_DIR/Screenshot 1.png" ]
  [ -z "$(ls -A "$REMOTE_DIR")" ]
}

@test "unsure stays, is reported once, and is not asked about again" {
  echo unsure >"$DESKTOP/odd.pdf"
  run "$SCRIPT"
  [ "$status" -eq 3 ]
  [[ "$output" == *"unsure: odd.pdf"* ]]
  [ -e "$DESKTOP/odd.pdf" ]
  rm -f "$TMP/classified"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$TMP/classified" ]
}

@test "a keep answer whose name could leave the filing folder is treated as unsure" {
  keep_line ../../escape withholding_2025_taro.pdf >"$DESKTOP/a.pdf"
  keep_line 2026/2026-11_x '../withholding_2025_taro.pdf' >"$DESKTOP/b.pdf"
  keep_line 2026/2026-11_x 'Withholding 2025.pdf' >"$DESKTOP/c.pdf"
  run "$SCRIPT"
  [ "$status" -eq 3 ]
  [ -e "$DESKTOP/a.pdf" ]
  [ -e "$DESKTOP/b.pdf" ]
  [ -e "$DESKTOP/c.pdf" ]
  [ -z "$(ls -A "$REMOTE_DIR")" ]
}

@test "an answer that is none of the three is unsure, and a failing classifier keeps the file" {
  echo "delete everything" >"$DESKTOP/a.pdf"
  run "$SCRIPT"
  [ "$status" -eq 3 ]
  [ -e "$DESKTOP/a.pdf" ]
  echo junk >"$DESKTOP/b.pdf"
  STUB_CLASSIFY_FAIL=1 run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"classifier failed, kept: b.pdf"* ]]
  [ -e "$DESKTOP/b.pdf" ]
}

@test "keeps the local file when the downloaded copy differs" {
  keep_line 2026/2026-11_x receipt_2026_taro.pdf >"$DESKTOP/a.pdf"
  STUB_CORRUPT=1 run "$SCRIPT"
  [ "$status" -eq 1 ]
  [ -e "$DESKTOP/a.pdf" ]
}

@test "keeps the local file when the upload fails" {
  keep_line 2026/2026-11_x receipt_2026_taro.heic >"$DESKTOP/IMG_0001.HEIC"
  STUB_UPLOAD_FAIL=1 run "$SCRIPT"
  [ "$status" -eq 1 ]
  [ -e "$DESKTOP/IMG_0001.HEIC" ]
}

@test "a different file already under that name is not overwritten, and this one waits as unsure" {
  mkdir -p "$REMOTE_DIR/2026/2026-11_x"
  echo older >"$REMOTE_DIR/2026/2026-11_x/receipt_2026_taro.pdf"
  keep_line 2026/2026-11_x receipt_2026_taro.pdf >"$DESKTOP/a.pdf"
  run "$SCRIPT"
  [ "$status" -eq 3 ]
  [ -e "$DESKTOP/a.pdf" ]
  [ "$(cat "$REMOTE_DIR/2026/2026-11_x/receipt_2026_taro.pdf")" = older ]
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "a keep name whose extension differs from the file's is unsure" {
  keep_line 2026/2026-11_x receipt_2026_taro.pdf >"$DESKTOP/IMG_0001.HEIC"
  run "$SCRIPT"
  [ "$status" -eq 3 ]
  [ -e "$DESKTOP/IMG_0001.HEIC" ]
}

@test "a destination without a trailing separator still files inside it" {
  keep_line 2026/2026-11_x receipt_2026_taro.pdf >"$DESKTOP/a.pdf"
  DRIVE_DEST="gdrive-paperwork:Paperwork" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -e "$REMOTE_DIR/Paperwork/2026/2026-11_x/receipt_2026_taro.pdf" ]
}

@test "leaves files outside the allow-list, hidden files and subfolders alone" {
  echo junk >"$DESKTOP/installer.dmg"
  echo junk >"$DESKTOP/.hidden.pdf"
  echo junk >"$DESKTOP/half.pdf.crdownload"
  echo junk >"$DESKTOP/pdf"
  mkdir "$DESKTOP/sub"
  echo junk >"$DESKTOP/sub/inner.pdf"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$(ls -A "$TRASH_DIR")" ]
}

@test "a file newer than the grace period stays" {
  echo junk >"$DESKTOP/fresh.pdf"
  MIN_AGE_MINUTES=60 run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -e "$DESKTOP/fresh.pdf" ]
}

@test "dry run classifies and lists, and changes nothing" {
  echo junk >"$DESKTOP/a.pdf"
  keep_line 2026/2026-11_x receipt_2026_taro.pdf >"$DESKTOP/b.pdf"
  TIDY_DRY_RUN=1 run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"would junk: a.pdf"* ]]
  [[ "$output" == *"would keep: b.pdf -> 2026/2026-11_x/receipt_2026_taro.pdf"* ]]
  [ -e "$DESKTOP/a.pdf" ]
  [ -e "$DESKTOP/b.pdf" ]
  [ -z "$(ls -A "$REMOTE_DIR")" ]
}

@test "keeps the file when the hash tool fails, rather than matching two empty hashes" {
  keep_line 2026/2026-11_x receipt_2026_taro.pdf >"$DESKTOP/a.pdf"
  for tool in sha256sum shasum; do
    printf '#!/bin/bash\nexit 1\n' >"$STUB/$tool"
    chmod +x "$STUB/$tool"
  done
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot hash, kept: a.pdf"* ]]
  [ -e "$DESKTOP/a.pdf" ]
}

@test "a folder that cannot be listed fails the run instead of looking empty" {
  printf '#!/bin/bash\necho "find: Operation not permitted" >&2\nexit 1\n' >"$STUB/find"
  chmod +x "$STUB/find"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot list $DESKTOP"* ]]
}

@test "a lock left by a dead run does not block the next one" {
  mkdir "$TMP/tidy_to_drive.lock"
  # A fixed old stamp: BSD and GNU touch agree on -t, not on -d.
  touch -t 202001010000 "$TMP/tidy_to_drive.lock"
  echo junk >"$DESKTOP/a.pdf"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$DESKTOP/a.pdf" ]
}

@test "a fresh lock skips this run" {
  mkdir "$TMP/tidy_to_drive.lock"
  echo junk >"$DESKTOP/a.pdf"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -e "$DESKTOP/a.pdf" ]
  [ -d "$TMP/tidy_to_drive.lock" ]
}

@test "rclone reading stdin does not swallow the rest of the list" {
  keep_line 2026/2026-11_x receipt_2026_a.pdf >"$DESKTOP/a.pdf"
  keep_line 2026/2026-11_x receipt_2026_b.pdf >"$DESKTOP/b.pdf"
  keep_line 2026/2026-11_x receipt_2026_c.pdf >"$DESKTOP/c.pdf"
  STUB_READ_STDIN=1 run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$(ls -A "$DESKTOP")" ]
}

@test "a missing source folder or a bad age is reported, not silently skipped" {
  TIDY_SOURCE_DIRS="$TMP/Destkop" run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no folder $TMP/Destkop"* ]]
  MIN_AGE_MINUTES=3d run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"whole number of minutes"* ]]
}

@test "a name with a backslash still hashes" {
  echo junk >"$DESKTOP/a\\b.pdf"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$(ls -A "$DESKTOP")" ]
}

@test "sweeps every folder in the list" {
  mkdir -p "$TMP/Downloads"
  echo junk >"$DESKTOP/a.pdf"
  echo junk >"$TMP/Downloads/b.pdf"
  TIDY_SOURCE_DIRS="$DESKTOP:$TMP/Downloads" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -e "$TRASH_DIR/a.pdf" ]
  [ -e "$TRASH_DIR/b.pdf" ]
}
