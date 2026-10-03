#!/bin/bash

# Pins KEYBINDINGS.md's "Terminal" table against config/ghostty/config's
# `keybind = ` lines, so a renamed or removed Ghostty keybind fails here
# instead of leaving the reference quietly wrong — the failure mode
# claudecode/rules/tooling.md names: a rule held up by remembering.
#
# First layer of #249. The other five sources that issue lists (tmux, zsh,
# Neovim, AeroSpace, Hammerspoon) are not covered yet; each needs its own
# per-syntax key extraction the same way this one does for Ghostty's.

set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
cd "$BASE_DIR" || exit 1

# Overridable so the bats tests can point at fixtures instead of the repo's
# own files.
GHOSTTY_CONFIG="${CHECK_KEYBINDINGS_GHOSTTY_CONFIG:-config/ghostty/config}"
DOC="${CHECK_KEYBINDINGS_DOC:-KEYBINDINGS.md}"

# Ghostty keybinds with no row of their own in the Terminal table: they are
# the "⌥+0~5 go to AeroSpace" footnote below it, not a row in it.
ALLOWED_UNDOCUMENTED=("alt+0" "alt+1" "alt+2" "alt+3" "alt+4" "alt+5")

# Canonicalize one key spec (a Ghostty trigger like "super+shift+o", or a
# KEYBINDINGS.md token already split down to one modifier+base combo) into
# a lowercase "ctrl+alt+shift+cmd+<base>" string, omitting absent modifiers,
# so both sides compare equal regardless of which words, symbols, or
# modifier order they started from.
canon() {
  local raw="${1#global:}"
  local have_ctrl=0 have_alt=0 have_shift=0 have_cmd=0
  local base="" part
  local IFS='+'
  read -ra parts <<<"$raw"
  for part in "${parts[@]}"; do
    case "$part" in
      super | cmd | '⌘') have_cmd=1 ;;
      alt | option | '⌥') have_alt=1 ;;
      ctrl | control | '⌃') have_ctrl=1 ;;
      shift | '⇧') have_shift=1 ;;
      digit_*) base="${part#digit_}" ;;
      arrow_left | '←') base="left" ;;
      arrow_right | '→') base="right" ;;
      arrow_up | '↑') base="up" ;;
      arrow_down | '↓') base="down" ;;
      *) base=$(printf '%s' "$part" | tr '[:upper:]' '[:lower:]') ;;
    esac
  done
  # Fixed order (not alphabetical, just consistent) so both sides of the
  # comparison always build the same string regardless of which order the
  # source listed its modifiers in.
  [ "$have_ctrl" -eq 1 ] && base="ctrl+${base}"
  [ "$have_alt" -eq 1 ] && base="alt+${base}"
  [ "$have_shift" -eq 1 ] && base="shift+${base}"
  [ "$have_cmd" -eq 1 ] && base="cmd+${base}"
  printf '%s\n' "$base"
}

# The Ghostty keybinds actually configured, one canonical key per line.
configured_keys() {
  local trig c allowed skip
  grep -E '^keybind = ' "$GHOSTTY_CONFIG" |
    sed -E 's/^keybind = //; s/=.*//' |
    while IFS= read -r trig; do
      c="$(canon "$trig")"
      skip=0
      for allowed in "${ALLOWED_UNDOCUMENTED[@]}"; do
        if [ "$c" = "$allowed" ]; then
          skip=1
          break
        fi
      done
      if [ "$skip" -eq 0 ]; then
        printf '%s\n' "$c"
      fi
    done | sort -u
}

# One key cell from the table ("⌘+1~9", "⌘+⌥+← / →", "F12", "¥") expanded into
# its canonical key(s), one per line: "/" alternates (sharing the first
# alternate's modifiers when the second has none of its own) and "~" ranges
# on the base key both become separate lines.
expand_cell() {
  local cell="$1" first second prefix base lo hi n mods_prefix
  if [[ "$cell" == *" / "* ]]; then
    first="${cell%% / *}"
    second="${cell##* / }"
    if [[ "$second" != *+* && "$first" == *+* ]]; then
      mods_prefix="${first%+*}+"
      expand_cell "$first"
      expand_cell "${mods_prefix}${second}"
      return
    fi
    expand_cell "$first"
    expand_cell "$second"
    return
  fi
  base="${cell##*+}"
  if [[ "$base" == *"~"* ]]; then
    prefix="${cell%+*}"
    if [ "$prefix" = "$cell" ]; then
      prefix=""
    else
      prefix="${prefix}+"
    fi
    lo="${base%~*}"
    hi="${base#*~}"
    for ((n = lo; n <= hi; n++)); do
      canon "${prefix}${n}"
    done
    return
  fi
  canon "$cell"
}

# The Terminal table's documented keys, one canonical key per line. Rows
# whose Action names a platform this script has no config for (Windows) are
# skipped — Ghostty is the macOS side only.
documented_keys() {
  awk '
    /^## Terminal/ { insection = 1; next }
    insection && /^---$/ { exit }
    insection && /^\| / { print }
  ' "$DOC" |
    grep -v '^| Key ' | grep -v '^|-----' |
    grep -v '(Windows only)' |
    sed -E 's/^\| *([^|]+) *\|.*/\1/' |
    sed -E 's/ *$//' |
    while IFS= read -r cell; do
      expand_cell "$cell"
    done | sort -u
}

configured="$(configured_keys)"
documented="$(documented_keys)"

rc=0

while IFS= read -r key; do
  if [ -z "$key" ]; then
    continue
  fi
  if ! grep -qxF "$key" <<<"$documented"; then
    echo "x Ghostty binds '$key' but KEYBINDINGS.md's Terminal table has no row for it"
    rc=1
  fi
done <<<"$configured"

while IFS= read -r key; do
  if [ -z "$key" ]; then
    continue
  fi
  if ! grep -qxF "$key" <<<"$configured"; then
    echo "x KEYBINDINGS.md's Terminal table names '$key' but no Ghostty keybind binds it"
    rc=1
  fi
done <<<"$documented"

exit "$rc"
