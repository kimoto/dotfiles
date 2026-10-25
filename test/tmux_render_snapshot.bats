#!/usr/bin/env bats

# tmux_render_snapshot.sh check is only as good as its normalizer: an
# attribute it drops is a change it can never report (the tmux 3.8 underline
# was one), and a difference no one can see that it keeps is a red CI run
# for nothing. The full draw needs the latest tmux and runs in CI's
# tmux_latest_test; these pin the normalizer on its own.

# One draw takes about three seconds, so the golden both check tests compare
# against is drawn once for the file.
setup_file() {
  command -v tmux >/dev/null 2>&1 || return 0
  export GOLDEN="$BATS_FILE_TMPDIR/golden.txt"
  TMUX_RENDER_GOLDEN="$GOLDEN" "$BATS_TEST_DIRNAME/../bin/tmux_render_snapshot.sh" update
}

setup() {
  SNAP="$BATS_TEST_DIRNAME/../bin/tmux_render_snapshot.sh"
  E=$'\033'
}

needs_golden() {
  command -v tmux >/dev/null 2>&1 || skip "needs tmux"
  [ -s "$GOLDEN" ]
}

norm() { printf '%s\n' "$1" | "$SNAP" normalize; }

@test "an underline on a tab is part of the look" {
  run norm "${E}[38;2;0;43;54m${E}[48;2;42;161;152m 1:a ${E}[4m 2:b "
  [ "$status" -eq 0 ]
  [ "$output" = "[fg=#002b36 bg=#2aa198] 1:a [fg=#002b36 bg=#2aa198 underscore] 2:b " ]
}

@test "an underline on padding is part of the look too" {
  run norm "${E}[38;2;0;43;54m${E}[4mx   "
  [ "$output" = "[fg=#002b36 underscore]x   " ]
}

@test "the fg of plain padding is not part of the look" {
  # The same blank cell drawn with two foregrounds looks the same.
  a="$(norm "${E}[48;2;7;54;66m${E}[38;2;1;1;1m   ${E}[38;2;2;2;2mx")"
  b="$(norm "${E}[48;2;7;54;66m${E}[38;2;9;9;9m   ${E}[38;2;2;2;2mx")"
  [ "$a" = "$b" ]
  [ "$a" = "[bg=#073642]   [fg=#020202 bg=#073642]x" ]
}

@test "the fg of padding is part of the look under a line or reverse" {
  # These draw blanks in the fg colour, so a new fg there is a change you see.
  for code in 4:underscore 7:reverse 9:strike 53:overline; do
    run norm "${E}[38;2;1;1;1mx${E}[${code%%:*}m   ${E}[0my"
    [ "$output" = "[fg=#010101]x[fg=#010101 ${code#*:}]   []y" ]
  done
}

@test "reset and the off codes end what they turned on" {
  run norm "${E}[1;4;7mA${E}[24mB${E}[22;27mC${E}[0;31mD"
  [ "$output" = "[bold reverse underscore]A[bold reverse]B[]C[fg=colour1]D" ]
}

@test "the clock does not move the snapshot" {
  run norm "x 2026-10-22 10:47"
  [ "$output" = "[]x <clock>" ]
}

@test "trailing default blanks are trimmed, as capture-pane does" {
  run norm "x   "
  [ "$output" = "[]x" ]
}

@test "check passes against a golden this tmux just drew" {
  needs_golden
  export TMUX_RENDER_GOLDEN="$GOLDEN"
  run "$SNAP" check
  [ "$status" -eq 0 ]
}

@test "check fails and shows the diff when the look moved" {
  needs_golden
  export TMUX_RENDER_GOLDEN="$BATS_TEST_TMPDIR/golden.txt"
  cp "$GOLDEN" "$TMUX_RENDER_GOLDEN"
  sed -i.bak '1s/^/moved/' "$TMUX_RENDER_GOLDEN"
  run "$SNAP" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"The look of .tmux.conf changed"* ]]
}
