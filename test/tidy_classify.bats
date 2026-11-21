#!/usr/bin/env bats

# Behavioural tests for bin/tidy_classify.sh. `claude` and `mdls` are stubs:
# the point is which files reach the model at all, what the model is told,
# and that its answer comes back as one tab-separated line.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(mktemp -d)"
  SCRIPT="$REPO_ROOT/bin/tidy_classify.sh"
  export CALLS="$TMP/claude.calls"
  STUB="$TMP/stubbin"
  mkdir -p "$STUB" "$TMP/files"
  cat >"$STUB/claude" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$@" >>"$CALLS"
printf '%s\n' "${STUB_ANSWER:-junk}"
STUBEOF
  cat >"$STUB/mdls" <<'STUBEOF'
#!/bin/bash
case "$3" in
  kMDItemIsScreenCapture) echo "${STUB_SCREEN:-(null)}" ;;
  kMDItemWhereFroms) printf '%s\n' "${STUB_WHERE:-(null)}" ;;
esac
STUBEOF
  chmod +x "$STUB/claude" "$STUB/mdls"
  PATH="$STUB:$PATH"
}

teardown() {
  rm -rf "$TMP"
}

@test "a screenshot by name is a shot without asking the model" {
  echo x >"$TMP/files/Screenshot 2026-11-21 at 10.00.00.png"
  run "$SCRIPT" "$TMP/files/Screenshot 2026-11-21 at 10.00.00.png"
  [ "$output" = shot ]
  [ ! -e "$CALLS" ]
}

@test "a screenshot by Spotlight's mark is a shot without asking the model" {
  echo x >"$TMP/files/IMG_1.png"
  STUB_SCREEN=1 run "$SCRIPT" "$TMP/files/IMG_1.png"
  [ "$output" = shot ]
  [ ! -e "$CALLS" ]
}

@test "anything else goes to the model, which reads with nothing but Read" {
  echo x >"$TMP/files/scan.pdf"
  run "$SCRIPT" "$TMP/files/scan.pdf"
  [ "$status" -eq 0 ]
  grep -qx -- '--tools' "$CALLS"
  grep -A1 -x -- '--tools' "$CALLS" | grep -qx Read
  grep -qx -- '--strict-mcp-config' "$CALLS"
}

@test "the download source reaches the prompt as a hint" {
  echo x >"$TMP/files/scan.pdf"
  STUB_WHERE='("https://www.city.example.jp/form.pdf")' run "$SCRIPT" "$TMP/files/scan.pdf"
  grep -q 'downloaded from: https://www.city.example.jp/form.pdf' "$CALLS"
}

@test "only the model's last non-empty line comes back, with <TAB> turned into tabs" {
  echo x >"$TMP/files/scan.pdf"
  STUB_ANSWER=$'Looking at it.\n\nkeep<TAB>2026/2026-11_x<TAB>receipt_2026_taro.pdf\n' \
    run "$SCRIPT" "$TMP/files/scan.pdf"
  [ "$output" = $'keep\t2026/2026-11_x\treceipt_2026_taro.pdf' ]
}
