#!/usr/bin/env bats

# Tests for bin/pc_checkup_diff.sh.
#
# The diff must flag what the allow list does not cover, report allowed
# entries that are gone, honour `*` prefixes, and refuse an allow entry
# without a reason. Inputs are tiny TSV files written per test.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/pc_checkup_diff.sh"
  SNAP="$BATS_TEST_TMPDIR/snap.tsv"
  ALLOW="$BATS_TEST_TMPDIR/allow.tsv"
}

@test "nothing new when every line is allowed" {
  printf 'login\trun:OneDrive\tC:\\od.exe\nsetting\tuac=on\t\n' >"$SNAP"
  printf '# comment\n\nlogin\trun:OneDrive\tsync\nsetting\tuac=on\tdefault\n' >"$ALLOW"
  run "$SCRIPT" "$SNAP" "$ALLOW"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "flags a line the allow list does not cover" {
  printf 'login\trun:OneDrive\tx\nlisten\tfoo:8080\t0.0.0.0\n' >"$SNAP"
  printf 'login\trun:OneDrive\tsync\n' >"$ALLOW"
  run "$SCRIPT" "$SNAP" "$ALLOW"
  [ "$status" -eq 1 ]
  [ "$output" = "$(printf 'new\tlisten\tfoo:8080\t0.0.0.0')" ]
}

@test "a changed setting value is new, the allowed value is gone" {
  printf 'setting\tfilevault=off\t\n' >"$SNAP"
  printf 'setting\tfilevault=on\tencrypted at rest\n' >"$ALLOW"
  run "$SCRIPT" "$SNAP" "$ALLOW"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "$(printf 'new\tsetting\tfilevault=off\t')" ]
  [ "${lines[1]}" = "$(printf 'gone\tsetting\tfilevault=on')" ]
}

@test "gone alone does not fail, and is sorted" {
  : >"$SNAP"
  printf 'login\tb\tr\nlogin\ta\tr\n' >"$ALLOW"
  run "$SCRIPT" "$SNAP" "$ALLOW"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(printf 'gone\tlogin\ta')" ]
  [ "${lines[1]}" = "$(printf 'gone\tlogin\tb')" ]
}

@test "a trailing star matches by prefix and counts as seen" {
  printf 'login\tservice:GoogleUpdaterService158.0\tx\n' >"$SNAP"
  printf 'login\tservice:GoogleUpdaterService*\tbrowser updates\n' >"$ALLOW"
  run "$SCRIPT" "$SNAP" "$ALLOW"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a prefix does not match another kind" {
  printf 'listen\tservice:x\t\n' >"$SNAP"
  printf 'login\tservice:*\tr\n' >"$ALLOW"
  run "$SCRIPT" "$SNAP" "$ALLOW"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "$(printf 'new\tlisten\tservice:x\t')" ]
}

@test "refuses an allow entry without a reason" {
  printf 'login\ta\tx\n' >"$SNAP"
  printf 'login\ta\t\n' >"$ALLOW"
  run "$SCRIPT" "$SNAP" "$ALLOW"
  [ "$status" -eq 2 ]
  [[ "$output" == *"has no reason"* ]]
}

@test "usage error on a missing file" {
  run "$SCRIPT" "$BATS_TEST_TMPDIR/nope" "$ALLOW"
  [ "$status" -eq 2 ]
}
