#!/usr/bin/env bats

# Tests for bin/cpu_window.sh --diff. What they pin down is who gets blamed:
# a respawned daemon that vanishes from the list, or a reused or exec'd pid
# charged a negative or inflated figure, sends the next "why is it slow" the
# wrong way.

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../bin/cpu_window.sh"
    TMP="$(mktemp -d)"
    export CPU_WINDOW_NCPU=8
    T0="Mon Oct 26 09:00:00 2026"
    T1="Tue Oct 27 07:00:05 2026"
}

teardown() {
    rm -rf "$TMP"
}

@test "a busy process gets its share of the window, per core and per machine" {
    printf '  100 %s  10:00.00 /usr/libexec/busyd\n' "$T0" >"$TMP/a"
    printf '  100 %s  10:30.00 /usr/libexec/busyd\n' "$T0" >"$TMP/b"
    run "$SCRIPT" --diff "$TMP/a" "$TMP/b" 30
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf ' 100.0\t  12.5\t100\t/usr/libexec/busyd')" ]
}

@test "a command with spaces keeps its full path, so app helpers stay apart" {
    printf '  7 %s  0:01.00 /A.app/Helper (Renderer).app/Helper (Renderer)\n  8 %s  0:01.00 /A.app/Helper (GPU)\n' \
        "$T0" "$T0" >"$TMP/a"
    printf '  7 %s  0:16.00 /A.app/Helper (Renderer).app/Helper (Renderer)\n  8 %s  0:04.00 /A.app/Helper (GPU)\n' \
        "$T0" "$T0" >"$TMP/b"
    run "$SCRIPT" --diff "$TMP/a" "$TMP/b" 30
    [ "${lines[0]}" = "$(printf '  50.0\t   6.2\t7\t/A.app/Helper (Renderer).app/Helper (Renderer)')" ]
    [ "${lines[1]}" = "$(printf '  10.0\t   1.2\t8\t/A.app/Helper (GPU)')" ]
}

@test "a process that started inside the window is shown as new with all its time" {
    printf '  1 %s  0:00.00 /sbin/launchd\n' "$T0" >"$TMP/a"
    printf '  1 %s  0:00.00 /sbin/launchd\n  42 %s  0:09.00 /usr/libexec/respawnd\n' "$T0" "$T1" >"$TMP/b"
    run "$SCRIPT" --diff "$TMP/a" "$TMP/b" 30
    [ "$output" = "$(printf '  30.0\t   3.8\t42\t/usr/libexec/respawnd  (new)')" ]
}

@test "a reused pid is counted as new, not as a negative or inflated delta" {
    printf '  42 %s  5:00.00 /usr/libexec/oldd\n' "$T0" >"$TMP/a"
    printf '  42 %s  0:03.00 /usr/libexec/newd\n' "$T1" >"$TMP/b"
    run "$SCRIPT" --diff "$TMP/a" "$TMP/b" 30
    [ "$output" = "$(printf '  10.0\t   1.2\t42\t/usr/libexec/newd  (new)')" ]
}

@test "an exec keeps the pid's earlier CPU time out of the window" {
    printf '  42 %s  10:00.00 /bin/zsh\n' "$T0" >"$TMP/a"
    printf '  42 %s  10:03.00 /usr/bin/python3\n' "$T0" >"$TMP/b"
    run "$SCRIPT" --diff "$TMP/a" "$TMP/b" 30
    [ "$output" = "$(printf '  10.0\t   1.2\t42\t/usr/bin/python3')" ]
}

@test "hours and days in ps time are parsed" {
    printf '  9 %s  1-02:03:04 /bin/d\n' "$T0" >"$TMP/a"
    printf '  9 %s  1-02:03:19 /bin/d\n' "$T0" >"$TMP/b"
    run "$SCRIPT" --diff "$TMP/a" "$TMP/b" 30
    [ "$output" = "$(printf '  50.0\t   6.2\t9\t/bin/d')" ]
}

@test "an idle process is left out" {
    printf '  3 %s  0:01.00 /bin/idle\n' "$T0" >"$TMP/a"
    printf '  3 %s  0:01.20 /bin/idle\n' "$T0" >"$TMP/b"
    run "$SCRIPT" --diff "$TMP/a" "$TMP/b" 30
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "a bad window is a usage error" {
    : >"$TMP/a"
    run "$SCRIPT" --diff "$TMP/a" "$TMP/a" 0
    [ "$status" -eq 2 ]
}
