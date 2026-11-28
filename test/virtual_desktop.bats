#!/usr/bin/env bats

# Tests for bin/virtual_desktop.sh. What they pin down is when it installs:
# a check that misses a tool leaves the agent with a dead screen, and one that
# always installs makes every start wait on apt.

load path_helpers

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../bin/virtual_desktop.sh"
    TMP="$(mktemp -d)"
    BIN="$TMP/bin"
    only_on_path "$BIN" bash grep cat
    export APT_LOG="$TMP/apt.log"
}

teardown() {
    rm -rf "$TMP"
}

# stub NAME BODY: a fake tool on the test PATH.
stub() {
    printf '#!/bin/bash\n%s\n' "$2" >"$BIN/$1"
    chmod +x "$BIN/$1"
}

all_tools_present() {
    stub Xvfb 'exit 0'
    stub openbox 'exit 0'
    stub import 'exit 0'
    stub fc-list 'echo "/usr/share/fonts/NotoSansCJK.ttc: Noto Sans CJK JP"'
    stub xdotool '[ "$1" = getdisplaygeometry ] && echo "1280 800"'
}

@test "nothing is missing when every tool and a Japanese font are there" {
    all_tools_present
    PATH="$BIN" run "$SCRIPT" missing
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "an empty machine needs the display, window manager, driver, screenshot and font" {
    PATH="$BIN" run "$SCRIPT" missing
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf 'xvfb\nopenbox\nxdotool\nimagemagick\nfonts-noto-cjk')" ]
}

@test "a machine without a Japanese font gets one, even with the X tools there" {
    all_tools_present
    stub fc-list 'exit 0'
    PATH="$BIN" run "$SCRIPT" missing
    [ "$output" = "fonts-noto-cjk" ]
}

@test "start on a ready machine with the display up runs no apt and prints DISPLAY" {
    all_tools_present
    stub apt-get 'echo "$@" >>"$APT_LOG"'
    PATH="$BIN" run "$SCRIPT" start
    [ "$status" -eq 0 ]
    [ "${lines[-1]}" = "export DISPLAY=:99" ]
    [ ! -e "$APT_LOG" ]
}

@test "start installs only what is missing" {
    all_tools_present
    rm "$BIN/openbox"
    stub apt-get 'echo "$@" >>"$APT_LOG"'
    PATH="$BIN" run "$SCRIPT" start
    [ "$status" -eq 0 ]
    [ "$(cat "$APT_LOG")" = "install -y -q openbox" ]
}
