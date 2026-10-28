#!/bin/bash
# End-to-end test for the translation shortcuts (hammerspoon/translate.lua) on
# the Mac they run on: real key presses into the running Hammerspoon, real
# translations from the API, and the result read off the clipboard and the
# popup window. test/translate.bats covers what translate.py sends; what only
# this can prove is the wiring — the hotkeys fire, the copy lands before the
# translation reads it, the popup opens and Esc closes it, and the screen
# region goes through screencapture.
#
# Run by hand on a Mac, never in CI: it needs the GUI, Hammerspoon's
# Accessibility and Screen Recording permissions, the API key in the Keychain,
# and it pays for four translations. The terminal running it needs
# Accessibility too (System Events sends the keys).
#
#   test/e2e/hammerspoon_translate_test.sh [--record DIR]
#
# --record keeps a screen recording of the whole run and a screenshot after
# each case in DIR, for whoever was not at the screen.
#
# Every key goes to the TextEdit document this test opens, and only after
# checking it is in front. A key sent to the terminal instead reaches the
# program running there — an Esc interrupts a Claude Code session mid-turn.
#
# The clipboard is put back on exit; the document is closed unsaved.
#
# shellcheck disable=SC2329  # the predicates run through expect, by name.
set -euo pipefail

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
RECORD=""
if [ "${1:-}" = --record ]; then
  RECORD="${2:?--record needs a directory}"
  mkdir -p "$RECORD"
fi
[ "$(uname)" = Darwin ] || { echo "SKIP: macOS only"; exit 0; }
pgrep -x Hammerspoon >/dev/null || { echo "FAIL: Hammerspoon is not running"; exit 1; }
[ -f "$HOME/.hammerspoon/translate.lua" ] || { echo "FAIL: no ~/.hammerspoon/translate.lua"; exit 1; }

# A translation takes a few seconds; the timeout is for a stuck API call, not
# a budget for the shortcut (the popup's busy state answers at once).
TRANSLATE_TIMEOUT=30
# Matches POPUP_WIDTH in translate.lua; the chooser and the console differ.
POPUP_WIDTH=520
SOURCE="The quick brown fox jumps over the lazy dog."
SENTINEL="hammerspoon-e2e-sentinel"

# screencapture writes the movie only when its time limit runs out — a signal
# loses it — so the limit is the whole run, and the end waits for it.
RECORD_SECONDS=100

TMP="$(mktemp -d)"
DOC="hammerspoon-e2e-$$.txt"
printf '%s\n' "$SOURCE" >"$TMP/$DOC"
pbpaste >"$TMP/clipboard"
textedit_was_running=""
pgrep -x TextEdit >/dev/null && textedit_was_running=1
recorder=""
cleanup() {
  osascript -e "tell application \"TextEdit\" to close (every document whose name is \"$DOC\") saving no" \
    >/dev/null 2>&1 || true
  # ⇧⌘C opens TextEdit's Colors panel; quitting takes it along.
  [ -n "$textedit_was_running" ] || osascript -e 'tell application "TextEdit" to quit' >/dev/null 2>&1 || true
  pbcopy <"$TMP/clipboard"
  rm -rf "$TMP"
  if [ -n "$recorder" ]; then
    echo "waiting for the ${RECORD_SECONDS}s recording to end: $RECORD/run.mov"
    wait "$recorder" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [ -n "$RECORD" ]; then
  screencapture -x -v -V "$RECORD_SECONDS" "$RECORD/run.mov" </dev/null &
  recorder=$!
fi
shots=0
snapshot() {
  [ -n "$RECORD" ] || return 0
  shots=$((shots + 1))
  screencapture -x "$RECORD/$(printf '%02d' "$shots")-$1.png"
}

# Brings the test's document to the front, then sends the System Events
# lines given — or sends nothing and fails if anything else is in front.
keys() {
  local lines=() line
  for line in "$@"; do lines+=(-e "$line"); done
  osascript \
    -e 'tell application "TextEdit" to activate' \
    -e "tell application \"TextEdit\" to set index of (first window whose name is \"$DOC\") to 1" \
    -e 'delay 0.4' \
    -e 'tell application "System Events" to set f to name of first process whose frontmost is true' \
    -e 'if f is not "TextEdit" then error "refusing to send keys: " & f & " is in front"' \
    "${lines[@]}" >/dev/null
}
se() { printf 'tell application "System Events" to %s' "$1"; }
SELECT_ALL="$(se 'keystroke "a" using command down')"
COPY="$(se 'keystroke "c" using command down')"
COPY_SHIFT="$(se 'keystroke "c" using {command down, shift down}')"
TRANSLATE_SELECTION="$(se 'key code 2 using {control down, command down, shift down}')"   # ⌃⌘⇧D
TRANSLATE_SCREEN="$(se 'key code 37 using {control down, command down, shift down}')"     # ⌃⌘⇧L
ESC="$(se 'key code 53')"

popups() {
  osascript -e 'tell application "System Events" to get size of windows of process "Hammerspoon"' |
    tr ',' '\n' | awk -v w="$POPUP_WIDTH" 'NR % 2 == 1 && $1 >= w - 1 && $1 <= w + 1' | wc -l | tr -d ' '
}
has_japanese() {
  perl -CS -Mutf8 -ne 'BEGIN { $f = 1 } $f = 0 if /[\p{Hiragana}\p{Katakana}\p{Han}]/; END { exit $f }'
}
running() { pgrep -f 'screencapture -i|translate.py' >/dev/null; }

clipboard_is_sentinel() { [ "$(pbpaste)" = "$SENTINEL" ]; }
popups_are() { [ "$(popups)" = "$1" ]; }
# Waits for a translation to replace the sentinel, then for the run to end:
# the clipboard is written once, after the whole answer has streamed in.
translated() {
  local deadline=$((SECONDS + TRANSLATE_TIMEOUT))
  until ! clipboard_is_sentinel && [ -n "$(pbpaste)" ] && ! running; do
    [ "$SECONDS" -lt "$deadline" ] || return 1
    sleep 0.5
  done
}
translated_into_japanese() { translated && pbpaste | has_japanese; }
translated_into_english() { translated && ! pbpaste | has_japanese; }
wait_popups() {
  local _
  for _ in $(seq 1 20); do
    popups_are "$1" && return 0
    sleep 0.1
  done
  return 1
}
nothing_running() { ! running; }

failures=0
# expect NAME COMMAND...: one check, reported with what was on screen.
expect() {
  local name="$1"
  shift
  if "$@"; then
    echo "ok   $name"
  else
    echo "FAIL $name (clipboard: $(pbpaste | head -c 80); popups: $(popups))"
    failures=$((failures + 1))
  fi
}
close_popup() { keys "$ESC"; wait_popups 0 || true; }
wait_screencapture() {
  local _
  for _ in $(seq 1 50); do pgrep -f 'screencapture -i' >/dev/null && break; sleep 0.1; done
  # The crosshair takes a moment after the process starts.
  sleep 0.5
}

open -a TextEdit "$TMP/$DOC"
for _ in $(seq 1 50); do
  osascript -e "tell application \"TextEdit\" to exists document \"$DOC\"" 2>/dev/null | grep -q true && break
  sleep 0.1
done
# Large enough for the screen case to read back from a screenshot.
osascript -e "tell application \"TextEdit\" to set size of text of document \"$DOC\" to 28"
close_popup

echo "== ⌃⌘⇧D translates the selection =="
printf '%s' "$SENTINEL" | pbcopy
keys "$SELECT_ALL" "$TRANSLATE_SELECTION"
expect "clipboard holds the Japanese translation" translated_into_japanese
expect "popup is open" popups_are 1
snapshot selection

echo "== Esc closes the popup =="
keys "$ESC"
expect "popup is gone" wait_popups 0

echo "== ⌘C+C translates what it copied =="
printf '%s' "$SENTINEL" | pbcopy
keys "$SELECT_ALL" "$COPY" 'delay 0.1' "$COPY"
# The first ⌘C itself replaces the sentinel with the source; wait past it.
sleep 1
expect "clipboard holds the Japanese translation" translated_into_japanese
expect "popup is open" popups_are 1
snapshot copy-copy
close_popup

echo "== ⌃⌘⇧D with nothing selected translates nothing =="
printf '%s' "$SENTINEL" | pbcopy
keys "$(se 'key code 124')" "$TRANSLATE_SELECTION"   # → collapses the selection
sleep 0.3
snapshot nothing-selected
sleep 1.7
expect "clipboard is untouched" clipboard_is_sentinel
expect "no popup" popups_are 0

echo "== ⇧⌘C+C asks for the language, and the answer is used =="
# ⇧⌘C is no copy in TextEdit, so the clipboard is filled first; ⇧⌘C+C
# translates whatever is on it. The pause outlasts DOUBLE_PRESS, or the ⌘C
# and the first ⇧⌘C would count as the pair.
keys "$SELECT_ALL" "$COPY" 'delay 0.8' "$COPY_SHIFT" 'delay 0.1' "$COPY_SHIFT" 'delay 1'
snapshot chooser
keys "$(se 'key code 125')" 'delay 0.2' "$(se 'key code 36')"   # ↓ to 英語へ, ⏎
sleep 1
# English into English has no Japanese, which the automatic target would give.
expect "translated into English" translated_into_english
expect "popup is open" popups_are 1
snapshot chooser-english
close_popup

echo "== ⌃⌘⇧L translates a screen region =="
printf '%s' "$SENTINEL" | pbcopy
read -r L T R _ < <(
  osascript -e "tell application \"TextEdit\" to get bounds of (first window whose name is \"$DOC\")" |
    tr -d ' ' | tr ',' ' ')
keys "$TRANSLATE_SCREEN"
wait_screencapture
swift "$DIR/mouse_drag.swift" $((L + 5)) $((T + 25)) $((R - 5)) $((T + 160))
expect "clipboard holds the Japanese translation" translated_into_japanese
expect "popup is open" popups_are 1
snapshot screen
close_popup

echo "== Esc during ⌃⌘⇧L cancels it =="
printf '%s' "$SENTINEL" | pbcopy
keys "$TRANSLATE_SCREEN"
wait_screencapture
snapshot screen-crosshair
keys "$ESC"
sleep 2
expect "nothing left running" nothing_running
expect "clipboard is untouched" clipboard_is_sentinel
expect "no popup" popups_are 0

echo
if [ "$failures" -eq 0 ]; then echo "PASS"; else echo "FAIL: $failures check(s)"; fi
exit $((failures > 0))
