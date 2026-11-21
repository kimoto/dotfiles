#!/usr/bin/env bats

# Tests for bin/seal.sh. `age` and `age-keygen` are stubs (CI does not install
# age): "encryption" is a header line, so what is checked is the script's own
# part, the tar in, the round trip, and that nothing is removed unless the
# sealed copy opens to the same bytes.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/seal.sh"
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/bin" "$TMP/work/album/inner"
  cat >"$TMP/bin/age-keygen" <<'STUB'
#!/bin/bash
[ "$1" = -y ] && [ -r "$2" ] && { echo age1stubrecipient; exit 0; }
[ "$1" = -y ] && [ $# -eq 1 ] && grep -q AGE-SECRET-KEY && { echo age1fromstdin; exit 0; }
exit 1
STUB
  cat >"$TMP/bin/age" <<'STUB'
#!/bin/bash
if [ "$1" = -d ]; then
  # age -d -i IDENTITY FILE; "-i -" reads the key from stdin.
  if [ "$3" = - ]; then grep -q AGE-SECRET-KEY || exit 1; fi
  tail -n +2 "$4"
  [ "${STUB_CORRUPT:-0}" = 1 ] && printf x
  exit 0
fi
# age -r RECIPIENT -o OUT
[ "${STUB_FAIL:-0}" = 1 ] && { cat >/dev/null; exit 1; }
# A file appearing in the folder while it is being sealed.
[ -n "${STUB_WRITE_DURING:-}" ] && echo late >"$STUB_WRITE_DURING"
{ echo "stub-age $1 $2"; cat; } >"$4"
STUB
  chmod +x "$TMP/bin/age" "$TMP/bin/age-keygen"
  export PATH="$TMP/bin:$PATH"
  export SEAL_IDENTITY="$TMP/key.txt"
  echo AGE-SECRET-KEY-STUB >"$SEAL_IDENTITY"
  echo one >"$TMP/work/album/a.mp4"
  echo two >"$TMP/work/album/inner/b.jpg"
}

teardown() {
  cd "$BATS_TEST_DIRNAME"
  rm -rf "$TMP"
}

@test "a folder is sealed beside itself, left alone, and opens to the same files" {
  run "$SCRIPT" "$TMP/work/album"
  [ "$status" -eq 0 ]
  [ -f "$TMP/work/album.tar.age" ]
  [ -d "$TMP/work/album" ]
  head -n 1 "$TMP/work/album.tar.age" | grep -q 'stub-age -r age1stubrecipient'
  mkdir "$TMP/out"
  run "$SCRIPT" --open "$TMP/work/album.tar.age" "$TMP/out"
  [ "$status" -eq 0 ]
  diff -r "$TMP/work/album" "$TMP/out/album"
}

@test "--remove deletes the original once the sealed copy checks out" {
  run "$SCRIPT" --remove "$TMP/work/album/"
  [ "$status" -eq 0 ]
  [ -f "$TMP/work/album.tar.age" ]
  [ ! -e "$TMP/work/album" ]
}

@test "a sealed copy that does not open to the same bytes is thrown away, and nothing is removed" {
  STUB_CORRUPT=1 run "$SCRIPT" --remove "$TMP/work/album"
  [ "$status" -ne 0 ]
  [ ! -e "$TMP/work/album.tar.age" ]
  [ ! -e "$TMP/work/album.tar.age.part" ]
  [ -f "$TMP/work/album/a.mp4" ]
}

@test "an encryption failure leaves no file behind and the original in place" {
  STUB_FAIL=1 run "$SCRIPT" --remove "$TMP/work/album"
  [ "$status" -ne 0 ]
  [ ! -e "$TMP/work/album.tar.age" ]
  [ ! -e "$TMP/work/album.tar.age.part" ]
  [ -d "$TMP/work/album" ]
}

@test "an existing sealed file is never overwritten" {
  echo older >"$TMP/work/album.tar.age"
  run "$SCRIPT" "$TMP/work/album"
  [ "$status" -ne 0 ]
  [ "$(cat "$TMP/work/album.tar.age")" = older ]
}

@test "without an identity nothing is written" {
  rm "$SEAL_IDENTITY"
  run "$SCRIPT" "$TMP/work/album"
  [ "$status" -ne 0 ]
  [[ "$output" == *age-keygen* ]]
  [ ! -e "$TMP/work/album.tar.age" ]
}

@test "a public key and a key command need no key file, and the key goes on stdin" {
  rm "$SEAL_IDENTITY"
  export SEAL_RECIPIENT=age1given SEAL_IDENTITY_CMD='echo AGE-SECRET-KEY-FROM-CMD'
  run "$SCRIPT" "$TMP/work/album"
  [ "$status" -eq 0 ]
  head -n 1 "$TMP/work/album.tar.age" | grep -q 'stub-age -r age1given'
  mkdir "$TMP/out"
  run "$SCRIPT" --open "$TMP/work/album.tar.age" "$TMP/out"
  [ "$status" -eq 0 ]
  diff -r "$TMP/work/album" "$TMP/out/album"
}

@test "a key command that prints no key fails the check, and nothing is removed" {
  rm "$SEAL_IDENTITY"
  export SEAL_RECIPIENT=age1given SEAL_IDENTITY_CMD='echo locked'
  run "$SCRIPT" --remove "$TMP/work/album"
  [ "$status" -ne 0 ]
  [ ! -e "$TMP/work/album.tar.age" ]
  [ -d "$TMP/work/album" ]
}

@test "the recipients file is used when no public key is given" {
  rm "$SEAL_IDENTITY"
  printf 'age1fromfile\n' >"$TMP/recipients"
  export SEAL_RECIPIENTS="$TMP/recipients" SEAL_IDENTITY_CMD='echo AGE-SECRET-KEY-X'
  run "$SCRIPT" "$TMP/work/album"
  [ "$status" -eq 0 ]
  head -n 1 "$TMP/work/album.tar.age" | grep -q "stub-age -R $TMP/recipients"
}

@test "a symlink is refused, so --remove cannot drop the link and leave the plaintext" {
  ln -s "$TMP/work/album" "$TMP/work/link"
  run "$SCRIPT" --remove "$TMP/work/link/"
  [ "$status" -ne 0 ]
  [ -L "$TMP/work/link" ]
  [ ! -e "$TMP/work/link.tar.age" ]
}

@test "\".\" seals the current folder beside it, not inside it" {
  cd "$TMP/work/album"
  run "$SCRIPT" .
  [ "$status" -eq 0 ]
  [ -f "$TMP/work/album.tar.age" ]
  [ -z "$(find "$TMP/work/album" -name '*.tar.age*')" ]
}

@test "--open never replaces a file that is already there" {
  run "$SCRIPT" "$TMP/work/album"
  [ "$status" -eq 0 ]
  echo edited >"$TMP/work/album/a.mp4"
  run "$SCRIPT" --open "$TMP/work/album.tar.age"
  [ "$status" -eq 0 ]
  [ "$(cat "$TMP/work/album/a.mp4")" = edited ]
}

@test "--remove keeps a folder that changed while it was being sealed" {
  STUB_WRITE_DURING="$TMP/work/album/new.jpg" run "$SCRIPT" --remove "$TMP/work/album"
  [ "$status" -ne 0 ]
  [[ "$output" == *changed* ]]
  [ -f "$TMP/work/album/new.jpg" ]
  [ -f "$TMP/work/album.tar.age" ]
}

@test "a key command alone is enough: the public key comes from it" {
  rm "$SEAL_IDENTITY"
  export SEAL_IDENTITY_CMD='echo AGE-SECRET-KEY-ONLY'
  run "$SCRIPT" "$TMP/work/album"
  [ "$status" -eq 0 ]
  head -n 1 "$TMP/work/album.tar.age" | grep -q 'stub-age -r age1fromstdin'
}
@test "a name starting with - is sealed, not read as an option" {
  mkdir "$TMP/work/-notes"
  echo n >"$TMP/work/-notes/n.txt"
  run "$SCRIPT" "$TMP/work/-notes"
  [ "$status" -eq 0 ]
  mkdir "$TMP/out"
  run "$SCRIPT" --open "$TMP/work/-notes.tar.age" "$TMP/out"
  [ "$status" -eq 0 ]
  diff -r "$TMP/work/-notes" "$TMP/out/-notes"
}

@test "a broken key file is reported as such, before anything is written" {
  printf '#!/bin/bash\nexit 1\n' >"$TMP/bin/age-keygen"
  run "$SCRIPT" "$TMP/work/album"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no public key"* ]]
  [ ! -e "$TMP/work/album.tar.age.part" ]
}

@test "an empty argument and an extra one are usage errors" {
  run "$SCRIPT" ""
  [ "$status" -ne 0 ]
  run "$SCRIPT" --open "$TMP/work/x.tar.age" "$TMP/out" extra
  [ "$status" -ne 0 ]
  [[ "$output" == *usage* ]]
}

@test "a single file is sealed too" {
  run "$SCRIPT" "$TMP/work/album/a.mp4"
  [ "$status" -eq 0 ]
  [ -f "$TMP/work/album/a.mp4.tar.age" ]
}
