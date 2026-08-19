#!/usr/bin/env bats

# Tests for bin/keybindings_new.sh, which copies KEYBINDINGS.md with recently
# added keys marked. The interesting property is what it does NOT mark: a row
# whose description was reworded, or that moved between sections, is not a new
# binding even though a diff shows it as an added line.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  SCRIPT="$REPO_ROOT/bin/keybindings_new.sh"
  TMP="$(mktemp -d)"
  export XDG_CACHE_HOME="$TMP/cache"

  # A fixture repo whose KEYBINDINGS.md has a genuine history: an old key, a
  # recent key, and a reword of the old key's description.
  mkdir -p "$TMP/repo/bin"
  cp "$SCRIPT" "$TMP/repo/bin/"
  FIX="$TMP/repo"
  git -C "$FIX" init -q

  write_doc() {
    cat >"$FIX/KEYBINDINGS.md"
  }
  commit_at() {
    local when="$1" msg="$2"
    git -C "$FIX" add -A
    GIT_AUTHOR_DATE="$when" GIT_COMMITTER_DATE="$when" git -C "$FIX" commit -q -m "$msg"
  }

  write_doc <<'DOC'
# Keybindings

| Key | Action |
|-----|--------|
| prefix + a | ancient binding |
DOC
  commit_at "$(date -u -r $(( $(date +%s) - 200 * 86400 )) +%Y-%m-%dT%H:%M:%S 2>/dev/null ||
              date -u -d "200 days ago" +%Y-%m-%dT%H:%M:%S)" "old"

  write_doc <<'DOC'
# Keybindings

| Key | Action |
|-----|--------|
| prefix + a | ancient binding |
| prefix + z | fresh binding |
DOC
  commit_at "$(date -u -r $(( $(date +%s) - 2 * 86400 )) +%Y-%m-%dT%H:%M:%S 2>/dev/null ||
              date -u -d "2 days ago" +%Y-%m-%dT%H:%M:%S)" "add z"

  write_doc <<'DOC'
# Keybindings

| Key | Action |
|-----|--------|
| prefix + a | ancient binding, now with a much better description |
| prefix + z | fresh binding |
DOC
  commit_at "$(date -u +%Y-%m-%dT%H:%M:%S)" "reword a"
}

teardown() {
  rm -rf "$TMP"
}

marked() { "$FIX/bin/keybindings_new.sh" --print "$@"; }

@test "marks a key added inside the window" {
  run marked
  [ "$status" -eq 0 ]
  [[ "$output" == *"🆕"*"prefix + z"* ]]
}

@test "does not mark a key whose description was merely reworded" {
  run marked
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^| prefix + a |' || {
    echo "row for 'prefix + a' was marked despite only its description changing"
    echo "$output"
    return 1
  }
}

@test "never marks the header or separator rows" {
  run marked
  [ "$status" -eq 0 ]
  [[ "$output" == *"| Key | Action |"* ]]
  [[ "$output" != *"🆕 Key"* ]]
  [[ "$output" != *"🆕 ---"* ]]
}

@test "a narrower window drops the older addition" {
  run marked --days 1
  [ "$status" -eq 0 ]
  [[ "$output" != *"🆕"* ]]
}

@test "a wider window covers both keys" {
  run marked --days 365
  [ "$status" -eq 0 ]
  # Both keys were introduced inside a year, so both count as new.
  [[ "$output" == *"🆕"*"prefix + a"* ]]
  [[ "$output" == *"🆕"*"prefix + z"* ]]
}

@test "without --print it prints the path to the marked copy" {
  run "$FIX/bin/keybindings_new.sh"
  [ "$status" -eq 0 ]
  [ -f "$output" ]
  grep -q "🆕" "$output"
}

@test "the second run reuses the cache and a doc edit invalidates it" {
  "$FIX/bin/keybindings_new.sh" >/dev/null
  local cached
  cached="$("$FIX/bin/keybindings_new.sh")"
  run grep -c "🆕" "$cached"
  [ "$output" = "1" ]

  printf '| prefix + q | brand new |\n' >>"$FIX/KEYBINDINGS.md"
  "$FIX/bin/keybindings_new.sh" >/dev/null
  run grep -c "🆕" "$cached"
  [ "$output" = "2" ]
}

@test "rejects an unknown argument" {
  run "$FIX/bin/keybindings_new.sh" --nope
  [ "$status" -eq 2 ]
}

@test "the real repo's document renders without marking a header" {
  run "$SCRIPT" --print
  [ "$status" -eq 0 ]
  [[ "$output" != *"🆕 Key"* ]]
}
