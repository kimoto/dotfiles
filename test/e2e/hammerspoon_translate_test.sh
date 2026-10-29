#!/bin/bash
# End-to-end test for the translation and rewrite shortcuts
# (hammerspoon/translate.lua) on the Mac they run on: real key presses into
# the running Hammerspoon, real answers from the API, and the result read off
# the clipboard and the popup window. test/translate.bats covers what
# translate.py sends; what only this can prove is the wiring — the hotkeys
# fire, the copy lands before the translation reads it, the popup opens and
# Esc closes it, and the screen region goes through screencapture.
#
# Run by hand on a Mac, never in CI: it needs the GUI, Hammerspoon's
# Accessibility and Screen Recording permissions, the API key in the Keychain,
# and it pays for five API calls. The terminal running it needs Accessibility
# too (System Events sends the keys).
#
#   test/e2e/hammerspoon_translate_test.sh [--record DIR]
#
# --record keeps a video and a screenshot of each case in DIR, for whoever
# was not at the screen.
#
# Every key goes to the TextEdit document this test opens, and only after
# checking it is in front. A key sent to the terminal instead reaches the
# program running there — an Esc interrupts a Claude Code session mid-turn.
#
# The rewrite uses the user's style file if there is one, and is never handed
# one by the test. The clipboard is put back on exit; the document is closed
# unsaved.
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
NOTES="・明日の定例 15時→16時に変更
・資料は今日中に共有する
・欠席なら連絡ほしい"
SENTINEL="hammerspoon-e2e-sentinel"
# screencapture writes a movie only when its time limit runs out — a signal
# loses it — so each case is recorded for a fixed length and waited out.
CASE_SECONDS=15

TMP="$(mktemp -d)"
DOC="hammerspoon-e2e-$$.txt"
printf '%s\n' "$SOURCE" >"$TMP/$DOC"
pbpaste >"$TMP/clipboard"
textedit_was_running=""
pgrep -x TextEdit >/dev/null && textedit_was_running=1
recorder=""
end_case() {
  [ -n "$recorder" ] || return 0
  wait "$recorder" 2>/dev/null || true
  recorder=""
}
cleanup() {
  end_case
  osascript -e "tell application \"TextEdit\" to close (every document whose name is \"$DOC\") saving no" \
    >/dev/null 2>&1 || true
  # ⇧⌘C opens TextEdit's Colors panel; quitting takes it along.
  [ -n "$textedit_was_running" ] || osascript -e 'tell application "TextEdit" to quit' >/dev/null 2>&1 || true
  pbcopy <"$TMP/clipboard"
  rm -rf "$TMP"
}
trap cleanup EXIT

cases=0
case_name=""
# begin_case SLUG TITLE: ends the case before, and records this one.
begin_case() {
  end_case
  cases=$((cases + 1))
  case_name="$(printf '%02d' "$cases")-$1"
  echo "== $2 =="
  [ -n "$RECORD" ] || return 0
  screencapture -x -v -V "$CASE_SECONDS" "$RECORD/$case_name.mov" </dev/null &
  recorder=$!
  # The recording starts a moment after the process does.
  sleep 1
}
snapshot() {
  [ -n "$RECORD" ] || return 0
  screencapture -x "$RECORD/$case_name.png"
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
REWRITE_SELECTION="$(se 'key code 13 using {control down, command down, shift down}')"    # ⌃⌘⇧W
TRANSLATE_SCREEN="$(se 'key code 37 using {control down, command down, shift down}')"     # ⌃⌘⇧L
ESC="$(se 'key code 53')"
set_document_text() {
  osascript -e 'on run argv' \
    -e "tell application \"TextEdit\" to set text of document \"$DOC\" to item 1 of argv" \
    -e "tell application \"TextEdit\" to set size of text of document \"$DOC\" to 28" \
    -e 'end run' "$1" >/dev/null
}

popups() {
  osascript -e 'tell application "System Events" to get size of windows of process "Hammerspoon"' |
    tr ',' '\n' | awk -v w="$POPUP_WIDTH" 'NR % 2 == 1 && $1 >= w - 1 && $1 <= w + 1' | wc -l | tr -d ' '
}
has_japanese() {
  perl -CS -Mutf8 -ne 'BEGIN { $f = 1 } $f = 0 if /[\p{Hiragana}\p{Katakana}\p{Han}]/; END { exit $f }'
}
running() { pgrep -f 'screencapture -i|translate.py' >/dev/null; }

clipboard_is() { [ "$(pbpaste)" = "$1" ]; }
clipboard_is_sentinel() { clipboard_is "$SENTINEL"; }
popups_are() { [ "$(popups)" = "$1" ]; }
# translated [COPIED]: waits for an answer to replace the sentinel (and the
# COPIED text the shortcut's own ⌘C put there), then for the run to end: the
# clipboard is written once, after the whole answer has streamed in.
translated() {
  local deadline=$((SECONDS + TRANSLATE_TIMEOUT))
  until ! clipboard_is_sentinel && [ -n "$(pbpaste)" ] && ! { [ -n "${1:-}" ] && clipboard_is "$1"; } &&
    ! running; do
    [ "$SECONDS" -lt "$deadline" ] || return 1
    sleep 0.5
  done
}
translated_into_japanese() { translated "$SOURCE" && pbpaste | has_japanese; }
translated_into_english() { translated && ! pbpaste | has_japanese; }
rewritten_in_japanese() { translated "$NOTES" && pbpaste | has_japanese; }
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
set_document_text "$SOURCE"
close_popup

begin_case selection "⌃⌘⇧D translates the selection, and Esc closes the popup"
printf '%s' "$SENTINEL" | pbcopy
keys "$SELECT_ALL" "$TRANSLATE_SELECTION"
expect "clipboard holds the Japanese translation" translated_into_japanese
expect "popup is open" popups_are 1
snapshot
keys "$ESC"
expect "popup is gone" wait_popups 0

begin_case copy-copy "⌘C+C translates what it copied"
printf '%s' "$SENTINEL" | pbcopy
keys "$SELECT_ALL" "$COPY" 'delay 0.1' "$COPY"
expect "clipboard holds the Japanese translation" translated_into_japanese
expect "popup is open" popups_are 1
snapshot
close_popup

begin_case nothing-selected "⌃⌘⇧D with nothing selected translates nothing"
printf '%s' "$SENTINEL" | pbcopy
keys "$(se 'key code 124')" "$TRANSLATE_SELECTION"   # → collapses the selection
sleep 0.3
snapshot
sleep 1.7
expect "clipboard is untouched" clipboard_is_sentinel
expect "no popup" popups_are 0

begin_case chooser "⇧⌘C+C asks for the language, and the answer is used"
# ⇧⌘C is no copy in TextEdit, so the clipboard is filled first; ⇧⌘C+C
# translates whatever is on it. The pause outlasts DOUBLE_PRESS, or the ⌘C
# and the first ⇧⌘C would count as the pair.
keys "$SELECT_ALL" "$COPY" 'delay 0.8' "$COPY_SHIFT" 'delay 0.1' "$COPY_SHIFT" 'delay 1'
snapshot
keys "$(se 'key code 125')" 'delay 0.2' "$(se 'key code 36')"   # ↓ to 英語へ, ⏎
sleep 1
# English into English has no Japanese, which the automatic target would give.
expect "translated into English" translated_into_english
expect "popup is open" popups_are 1
close_popup

begin_case screen "⌃⌘⇧L translates a screen region"
printf '%s' "$SENTINEL" | pbcopy
read -r L T R _ < <(
  osascript -e "tell application \"TextEdit\" to get bounds of (first window whose name is \"$DOC\")" |
    tr -d ' ' | tr ',' ' ')
keys "$TRANSLATE_SCREEN"
wait_screencapture
swift "$DIR/mouse_drag.swift" $((L + 5)) $((T + 25)) $((R - 5)) $((T + 160))
expect "clipboard holds the Japanese translation" translated_into_japanese
expect "popup is open" popups_are 1
snapshot
close_popup

begin_case screen-cancelled "a cancelled ⌃⌘⇧L translates nothing"
printf '%s' "$SENTINEL" | pbcopy
keys "$TRANSLATE_SCREEN"
wait_screencapture
snapshot
# Stopped, not sent Esc: while the crosshair is up, TextEdit still reports
# itself in front but an Esc can land in the terminal. Both leave the same
# empty file behind, which is what translate.py has to handle.
pkill -TERM -f 'screencapture -i' || true
sleep 2
expect "nothing left running" nothing_running
expect "clipboard is untouched" clipboard_is_sentinel
expect "no popup" popups_are 0

set_document_text "$NOTES"

begin_case rewrite "⌃⌘⇧W rewrites the notes as a message"
printf '%s' "$SENTINEL" | pbcopy
keys "$SELECT_ALL" "$REWRITE_SELECTION"
expect "clipboard holds a Japanese message, not the notes" rewritten_in_japanese
expect "popup is open" popups_are 1
snapshot
close_popup
end_case

echo
if [ "$failures" -eq 0 ]; then echo "PASS"; else echo "FAIL: $failures check(s)"; fi
exit $((failures > 0))
