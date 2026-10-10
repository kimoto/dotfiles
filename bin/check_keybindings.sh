#!/bin/bash

# Pins KEYBINDINGS.md's "Terminal" and "AeroSpace" tables against
# config/ghostty/config's `keybind = ` lines and .aerospace.toml's
# `key = command` bindings, so a renamed or removed keybind fails here
# instead of leaving the reference quietly wrong — the failure mode
# claudecode/rules/tooling.md names: a rule held up by remembering.
#
# Two layers of #249 so far (Ghostty, AeroSpace). The other three sources
# that issue lists (tmux, zsh, Neovim, Hammerspoon) are not covered yet;
# each needs its own per-syntax key extraction the same way these two do.

set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
cd "$BASE_DIR" || exit 1

# Overridable so the bats tests can point at fixtures instead of the repo's
# own files.
GHOSTTY_CONFIG="${CHECK_KEYBINDINGS_GHOSTTY_CONFIG:-config/ghostty/config}"
AEROSPACE_CONFIG="${CHECK_KEYBINDINGS_AEROSPACE_CONFIG:-.aerospace.toml}"
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

# One key cell from the table ("⌘+1~9", "⌘+⌥+← / →", "⌥+h/j/k/l", "F12", "¥")
# expanded into its canonical key(s), one per line: "/" alternates (sharing
# the first alternate's modifiers when the second has none of its own),
# "~" ranges and letter-list "/" slashes (no surrounding spaces) on the base
# key all become separate lines.
expand_cell() {
  local cell="$1" first second prefix base lo hi n mods_prefix part letters
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
  if [[ "$base" == *"/"* && "$base" != "/" ]]; then
    prefix="${cell%+*}"
    if [ "$prefix" = "$cell" ]; then
      prefix=""
    else
      prefix="${prefix}+"
    fi
    local IFS='/'
    read -ra letters <<<"$base"
    for part in "${letters[@]}"; do
      canon "${prefix}${part}"
    done
    return
  fi
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

# Canonicalize an AeroSpace binding key spec ("alt-shift-h", "alt-slash",
# "shift-down") the same way canon() does for the doc side: translate
# AeroSpace's symbol words to the literal character KEYBINDINGS.md uses,
# then hand the "+"-joined result to canon() so both sides normalize through
# the same modifier-order logic.
aerospace_canon() {
  local raw="$1" seg out="" sep=""
  local IFS='-'
  local -a segs
  read -ra segs <<<"$raw"
  for seg in "${segs[@]}"; do
    case "$seg" in
      slash) seg="/" ;;
      comma) seg="," ;;
      minus) seg="-" ;;
      equal) seg="=" ;;
      semicolon) seg=";" ;;
    esac
    out="${out}${sep}${seg}"
    sep="+"
  done
  canon "$out"
}

# The bindings actually configured in one [mode.*.binding] table of
# .aerospace.toml, one canonical key per line. $1 is the exact `[mode...]`
# header line; extraction stops at the next line starting with "[".
aerospace_configured_keys() {
  local section="$1"
  awk -v start="$section" '
    $0 == start { insection = 1; next }
    insection && /^\[/ { exit }
    insection { print }
  ' "$AEROSPACE_CONFIG" |
    grep -E '^[[:space:]]*[A-Za-z0-9_-]+[[:space:]]*=' |
    sed -E 's/^[[:space:]]*([A-Za-z0-9_-]+)[[:space:]]*=.*/\1/' |
    while IFS= read -r spec; do
      aerospace_canon "$spec"
    done | sort -u
}

# The Key column of the markdown table between two heading lines, as raw
# cell text (one per line) — shared by every documented_keys()-style
# function below. $1/$2 are grep -E patterns matched against whole lines.
# $3, if given, is a grep -E pattern for whole rows (Key *and* Action
# columns) to drop before the Key column is extracted — matching against
# the Key column alone would be too late to see text like "(Windows only)"
# that lives in Action.
table_cells() {
  local start_re="$1" stop_re="$2" exclude_re="${3:-}" rows
  rows="$(awk -v start="$start_re" -v stop="$stop_re" '
    $0 ~ start { insection = 1; next }
    insection && $0 ~ stop { exit }
    insection && /^\| / { print }
  ' "$DOC" | grep -v '^| Key ' | grep -v '^|-----')"
  if [ -n "$exclude_re" ]; then
    rows="$(grep -v -E "$exclude_re" <<<"$rows")"
  fi
  sed -E 's/^\| *([^|]+) *\|.*/\1/' <<<"$rows" | sed -E 's/ *$//'
}

# The Terminal table's documented keys, one canonical key per line. Rows
# whose Action names a platform this script has no config for (Windows) are
# skipped — Ghostty is the macOS side only.
documented_keys() {
  table_cells '^## Terminal' '^---$' '\(Windows only\)' |
    while IFS= read -r cell; do
      expand_cell "$cell"
    done | sort -u
}

# The "## AeroSpace" table's documented keys (main binding mode), one
# canonical key per line.
aerospace_documented_keys() {
  table_cells '^## AeroSpace' '^### Service mode' |
    while IFS= read -r cell; do
      expand_cell "$cell"
    done | sort -u
}

# The "### Service mode" table's documented keys, one canonical key per
# line.
aerospace_service_documented_keys() {
  table_cells '^### Service mode' '^---$' |
    while IFS= read -r cell; do
      expand_cell "$cell"
    done | sort -u
}

# Compares a configured key set against a documented key set and prints one
# line per mismatch in either direction. $1/$3 name the two sides for the
# message; $2/$4 are their newline-separated canonical key sets.
compare_keys() {
  local config_name="$1" config_keys="$2" doc_name="$3" doc_keys="$4"
  local key found=0
  while IFS= read -r key; do
    if [ -z "$key" ]; then
      continue
    fi
    if ! grep -qxF "$key" <<<"$doc_keys"; then
      echo "x $config_name binds '$key' but $doc_name has no row for it"
      found=1
    fi
  done <<<"$config_keys"
  while IFS= read -r key; do
    if [ -z "$key" ]; then
      continue
    fi
    if ! grep -qxF "$key" <<<"$config_keys"; then
      echo "x $doc_name names '$key' but no $config_name binds it"
      found=1
    fi
  done <<<"$doc_keys"
  return "$found"
}

rc=0

compare_keys "Ghostty" "$(configured_keys)" \
  "KEYBINDINGS.md's Terminal table" "$(documented_keys)" || rc=1

compare_keys "AeroSpace's main binding mode" "$(aerospace_configured_keys '[mode.main.binding]')" \
  "KEYBINDINGS.md's AeroSpace table" "$(aerospace_documented_keys)" || rc=1

compare_keys "AeroSpace's service binding mode" "$(aerospace_configured_keys '[mode.service.binding]')" \
  "KEYBINDINGS.md's Service mode table" "$(aerospace_service_documented_keys)" || rc=1

exit "$rc"
