#!/bin/bash

# Pins eight of KEYBINDINGS.md's tables against the configs that bind their
# keys: Terminal (config/ghostty/config's `keybind = ` lines), AeroSpace and
# Service mode (.aerospace.toml's `key = command` bindings), tmux's With
# prefix and Copy mode (.tmux.conf), Text editing (hammerspoon/init.lua's
# remaps, in one direction: the rest of that table is macOS built-in), and
# zsh's keys (.zshrc's `bindkey` lines) and Abbreviations
# (config/zsh/abbr.zsh's ABBR_MAP), and Neovim's Space (leader) keys
# (config/nvim/lua's `vim.keymap.set` lines). A
# renamed or removed keybind fails here instead of leaving the reference
# quietly wrong — the failure mode claudecode/rules/tooling.md names: a rule
# held up by remembering.
#
# Not covered yet (#249): tmux's root table, whose rows name the Mac keys
# (⌘, ⌥⌘) that Ghostty translates before tmux sees them, so checking it needs
# that translation, not just .tmux.conf; Neovim's non-leader keys (Ctrl,
# Tab, g-prefixed LSP maps, insert-mode completion), whose cells mix
# plugin defaults and builtins with maps; zsh's Shell helpers, which are functions, not keys;
# and the tables no config here binds.

set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
cd "$BASE_DIR" || exit 1

# Overridable so the bats tests can point at fixtures instead of the repo's
# own files.
GHOSTTY_CONFIG="${CHECK_KEYBINDINGS_GHOSTTY_CONFIG:-config/ghostty/config}"
AEROSPACE_CONFIG="${CHECK_KEYBINDINGS_AEROSPACE_CONFIG:-.aerospace.toml}"
HAMMERSPOON_CONFIG="${CHECK_KEYBINDINGS_HAMMERSPOON_CONFIG:-hammerspoon/init.lua}"
TMUX_CONFIG="${CHECK_KEYBINDINGS_TMUX_CONFIG:-.tmux.conf}"
ZSHRC="${CHECK_KEYBINDINGS_ZSHRC:-.zshrc}"
ABBR_CONFIG="${CHECK_KEYBINDINGS_ABBR_CONFIG:-config/zsh/abbr.zsh}"
NVIM_DIR="${CHECK_KEYBINDINGS_NVIM_DIR:-config/nvim/lua}"
DOC="${CHECK_KEYBINDINGS_DOC:-KEYBINDINGS.md}"

# Ghostty keybinds with no row of their own in the Terminal table: they are
# the "⌥+0~5 go to AeroSpace" footnote below it, not a row in it.
ALLOWED_UNDOCUMENTED=("alt+0" "alt+1" "alt+2" "alt+3" "alt+4" "alt+5")

# Rows of the tmux "With prefix" table whose key .tmux.conf never binds,
# each bound somewhere this script does not parse.
TMUX_PREFIX_BOUND_ELSEWHERE=(
  "m"     # tmux's own default: mark pane
  "Tab"   # tmux 3.8's own default: window picker
  "g"     # tmux 3.8's own default: floating pane placement
  "*"     # tmux 3.7's own default: new floating pane
  "f"     # config/tmux-agent-status/agent-status.tmux, its own default key
  "F"     # tmux-fzf's default key
  "Enter" # tmux-menus' second default trigger
  "C-s"   # tmux-resurrect's default save key
  "C-r"   # tmux-resurrect's default restore key
)

# Rows of the zsh table whose key .zshrc never binds with its own `bindkey`.
ZSH_BOUND_ELSEWHERE=(
  "ctrl+r" # fzf's key-bindings.zsh (sheldon plugin): history search
  "ctrl+t" # fzf's key-bindings.zsh (sheldon plugin): file picker
  # zsh's own emacs keymap, which `bindkey -e` selects.
  "ctrl+a" "ctrl+e" "ctrl+w" "ctrl+u" "ctrl+l" "alt+b" "alt+f" "alt+d"
)

# Space rows of the Neovim tables that no `vim.keymap.set` here binds.
NVIM_LEADER_BOUND_ELSEWHERE=(
  "Space+j" # any-jump.vim's own default mapping
)

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
      # Ghostty's physical key names, shown in the doc by their US symbol.
      bracket_left) base="[" ;;
      bracket_right) base="]" ;;
      quote) base="'" ;;
      backslash) base="\\" ;;
      semicolon) base=";" ;;
      minus) base="-" ;;
      # Only an uppercase key pays for tr: macOS's bash 3.2 has no ${part,,},
      # and a process per key was most of this script's run time.
      *[[:upper:]]*) base=$(printf '%s' "$part" | tr '[:upper:]' '[:lower:]') ;;
      *) base="$part" ;;
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

# The remaps hammerspoon/init.lua makes, one canonical key per line:
# `remapKey({"alt"}, "b", ...)` gives "alt+b".
hammerspoon_configured_keys() {
  grep -E '^[[:space:]]*remapKey\(' "$HAMMERSPOON_CONFIG" |
    sed -E 's/^[[:space:]]*remapKey\(\{([^}]*)\},[[:space:]]*"([^"]+)".*/\1,\2/' |
    tr -d '" ' |
    tr ',' '+' |
    while IFS= read -r spec; do
      canon "$spec"
    done | sort -u
}

# Normalize one tmux key name: drop the quotes .tmux.conf needs around
# punctuation ('[', "C-M-'"), and spell the doc's "Ctrl-s" as tmux's "C-s".
# Case is kept: tmux binds m and M separately.
tmux_canon() {
  local k="$1"
  # A lone quote is the key itself (the doc's `prefix + "`), not quoting.
  if [ "${#k}" -gt 1 ]; then
    k="${k#[\"\']}"
    k="${k%[\"\']}"
  fi
  k="${k/#Ctrl-/C-}"
  printf '%s\n' "$k"
}

# The keys .tmux.conf binds in one key table ("prefix", "root", or a -T
# table such as "copy-mode-vi"), one per line. Every `bind-key` counts,
# including those inside if-shell strings, since each of them is a binding
# some tmux version gets; `unbind-key` does not.
tmux_configured_keys() {
  local table="$1" a b c t k
  grep -vE '^[[:space:]]*#' "$TMUX_CONFIG" |
    grep -oE '(^|[^a-z-])bind-key( -N "[^"]*")?( -r)?( -n| -T [A-Za-z-]+)? [^ ]+' |
    sed -E 's/^[^b]?bind-key( -N "[^"]*")?( -r)?//' |
    while read -r a b c; do
      case "$a" in
        -n) t=root k="$b" ;;
        -T) t="$b" k="$c" ;;
        *) t=prefix k="$a" ;;
      esac
      if [ "$t" = "$table" ]; then
        tmux_canon "$k"
      fi
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
  ' "$DOC" | grep -vE '^\| (Key|Word) +\|' | grep -v '^|-----')"
  if [ -n "$exclude_re" ]; then
    rows="$(grep -v -E "$exclude_re" <<<"$rows")"
  fi
  # A key cell can hold the | key only escaped, as \|, which must not end it.
  sed -E 's/\\\|/@PIPE@/g; s/^\| *([^|]+) *\|.*/\1/' <<<"$rows" | sed -E 's/ *$//; s/@PIPE@/|/g'
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

# The "Text editing" table's documented keys, one canonical key per line.
# "(Windows only)" rows are skipped, as in the Terminal table.
text_editing_documented_keys() {
  table_cells '^## Text editing' '^---$' '\(Windows only\)' |
    while IFS= read -r cell; do
      expand_cell "$cell"
    done | sort -u
}

# The tmux "With prefix" table's documented keys, one per line: every
# "prefix + <key>" in a cell, so "prefix + \ (or prefix + Enter)" gives
# both. Keys in TMUX_PREFIX_BOUND_ELSEWHERE are left out.
tmux_prefix_documented_keys() {
  local key allowed skip
  table_cells '^### With prefix' '^### ' |
    grep -oE 'prefix \+ [^ ,)]+' |
    sed -E 's/^prefix \+ //' |
    while IFS= read -r key; do
      key="$(tmux_canon "$key")"
      skip=0
      for allowed in "${TMUX_PREFIX_BOUND_ELSEWHERE[@]}"; do
        if [ "$key" = "$allowed" ]; then
          skip=1
          break
        fi
      done
      if [ "$skip" -eq 0 ]; then
        printf '%s\n' "$key"
      fi
    done | sort -u
}

# The tmux "Copy mode (vi)" table's documented keys, one per line.
tmux_copy_mode_documented_keys() {
  table_cells '^### Copy mode' '^---$' |
    while IFS= read -r cell; do
      tmux_canon "$cell"
    done | sort -u
}

# One zsh key sequence as bindkey reads it ("^X^N", "^\\", "^[d", "\ef") in
# the doc's canonical form: each keystroke through canon(), chords joined by
# a space ("ctrl+x ctrl+n"). "^[" and "\e" are Escape, the Alt prefix.
zsh_canon() {
  local s="$1" out="" key mod
  while [ -n "$s" ]; do
    mod=""
    if [ "${s:0:2}" = '^[' ] || [ "${s:0:2}" = '\e' ]; then
      mod="alt+"
      s="${s:2}"
    fi
    if [ "${s:0:1}" = '^' ] && [ "${#s}" -ge 2 ]; then
      mod="${mod}ctrl+"
      s="${s:1}"
    fi
    # bindkey's own escape: \\ is one backslash key.
    if [ "${s:0:2}" = "\\\\" ]; then
      key="\\"
      s="${s:2}"
    else
      key="${s:0:1}"
      s="${s:1}"
    fi
    out="${out:+$out }$(canon "${mod}${key}")"
  done
  printf '%s\n' "$out"
}

# The keys .zshrc binds with `bindkey KEY WIDGET` in the keymap the shell
# uses (none named, or `-M emacs` / `-M main`), one canonical key per line.
# Other options (`-e`, `-s`, `-M viins`) are not a binding the table lists.
zsh_configured_keys() {
  local line key
  local q="'"
  local re="^[[:space:]]*bindkey([[:space:]]+-M[[:space:]]+(emacs|main))?[[:space:]]+"
  re+="(\"([^\"]*)\"|${q}([^${q}]*)${q}|([^-[:space:]][^[:space:]]*))[[:space:]]"
  while IFS= read -r line; do
    [[ "$line" =~ $re ]] || continue
    if [ -n "${BASH_REMATCH[4]}" ]; then
      # Double quotes: the shell turns \\ into one backslash before bindkey.
      key="${BASH_REMATCH[4]//\\\\/\\}"
    else
      key="${BASH_REMATCH[5]}${BASH_REMATCH[6]}"
    fi
    zsh_canon "$key"
  done <"$ZSHRC" | sort -u
}

# The zsh table's documented keys, one canonical key per line. A cell is
# either alternates ("⌃+A / E") or one chord of space-separated keystrokes
# ("⌃+X ⌃+N").
zsh_documented_keys() {
  local cell part out
  local -a parts
  table_cells '^## zsh' '^### ' |
    while IFS= read -r cell; do
      if [[ "$cell" == *" / "* ]]; then
        expand_cell "$cell"
        continue
      fi
      # read -a, not an unquoted $cell: the "?" of "⌃+X ?" would glob.
      read -ra parts <<<"$cell"
      out=""
      for part in "${parts[@]}"; do
        out="${out:+$out }$(canon "$part")"
      done
      printf '%s\n' "$out"
    done | sort -u
}

# The words abbr.zsh's ABBR_MAP expands, one per line: each entry line
# (indented word, then a quoted value) inside `typeset -gA ABBR_MAP=(` ...
# `)`. Exits non-zero when no entry is found, so a renamed or reshaped map
# fails instead of comparing an empty set.
abbr_configured_words() {
  awk '
    /^typeset -gA ABBR_MAP=\(/ { inmap = 1; next }
    inmap && /^[[:space:]]*\)/ { exit }
    inmap && /^[[:space:]]+[A-Za-z0-9_-]+[[:space:]]+["\047]/ { print $1; n++ }
    END { if (!n) { print "x no ABBR_MAP entries found" > "/dev/stderr"; exit 1 } }
  ' "$ABBR_CONFIG" | sort -u
}

# The Abbreviations table's documented words, backticks dropped.
abbr_documented_words() {
  table_cells '^### Abbreviations' '^### ' | tr -d '`' | sort -u
}

# The leader keys config/nvim's Lua maps, one "Space+<keys>" per line:
# every `'<leader>xx'` lhs of a `vim.keymap.set` line, and a
# `'<leader>' .. i` lhs expanded over the `for i = lo, hi do` above it.
# Exits non-zero when none is found, so a moved config fails instead of
# comparing an empty set.
nvim_configured_leader_keys() {
  find "$NVIM_DIR" -name '*.lua' -exec cat {} + |
    awk '
      /^[[:space:]]*--/ { next }
      match($0, /for [A-Za-z_]+ = [0-9]+, *[0-9]+ do/) {
        split(substr($0, RSTART + 4, RLENGTH - 7), f, /[ =,]+/)
        var = f[1]; lo = f[2]; hi = f[3]
      }
      /keymap\.set\(/ && match($0, /["\047]<leader>[^"\047]*["\047]( \.\. [A-Za-z_]+)?/) {
        lhs = substr($0, RSTART + 9, RLENGTH - 9)
        if (lhs ~ / \.\. /) {
          split(lhs, g, /["\047] \.\. /)
          if (g[2] != var) { print "x cannot expand <leader> .. " g[2] > "/dev/stderr"; bad = 1; next }
          for (n = lo; n <= hi; n++) { print "Space+" g[1] n; found++ }
        } else {
          print "Space+" substr(lhs, 1, length(lhs) - 1); found++
        }
      }
      END {
        if (!found) print "x no <leader> maps found under the Neovim config" > "/dev/stderr"
        if (!found || bad) exit 1
      }
    ' | sort -u
}

# The Space keys the Neovim tables name, one "Space+<keys>" per line. A cell
# holds alternates ("Space+n / p", "Space+dr / Space+dl", the second sharing
# the first's Space when it has none of its own) and "~" ranges
# ("Space+1~6").
nvim_documented_leader_keys() {
  local cell part keys lo hi n
  # A variable, not $'\n' inside the expansion: bash 3.2 keeps that literal.
  local nl=$'\n'
  table_cells '^## Neovim' '^---$' |
    grep -E '(^|[ /])Space\+' |
    while IFS= read -r cell; do
      while IFS= read -r part; do
        keys="${part#Space+}"
        if [[ "$keys" == *"~"* ]]; then
          lo="${keys%~*}"
          hi="${keys#*~}"
          for ((n = lo; n <= hi; n++)); do
            printf 'Space+%s\n' "$n"
          done
        else
          printf 'Space+%s\n' "$keys"
        fi
      done <<<"${cell// \/ /$nl}"
    done | sort -u
}

# Prints one line per configured key with no documented row. $1/$3 name the
# two sides for the message; $2/$4 are their newline-separated canonical key
# sets.
compare_config_to_doc() {
  local config_name="$1" config_keys="$2" doc_name="$3" doc_keys="$4"
  local key found=0
  while IFS= read -r key; do
    echo "x $config_name binds '$key' but $doc_name has no row for it"
    found=1
  done < <(keys_missing_from "$doc_keys" "$config_keys")
  return "$found"
}

# The non-empty lines of $2 that are not a whole line of $1, in $2's order.
# One grep for the whole set rather than one per key.
keys_missing_from() {
  grep -vxF -e '' -f <(printf '%s\n' "$1") <<<"$2" || true
}

# compare_config_to_doc, plus one line per documented key no config binds.
# $5, if given, holds keys bound somewhere this script does not parse: a
# row for one needs no config, but the config binding one still needs a row.
compare_keys() {
  local config_name="$1" config_keys="$2" doc_name="$3" doc_keys="$4"
  local bound_elsewhere="${5:-}"
  local key found=0
  compare_config_to_doc "$1" "$2" "$3" "$4" || found=1
  while IFS= read -r key; do
    echo "x $doc_name names '$key' but no $config_name binds it"
    found=1
  done < <(keys_missing_from "$config_keys"$'\n'"$bound_elsewhere" "$doc_keys")
  return "$found"
}

rc=0

compare_keys "Ghostty" "$(configured_keys)" \
  "KEYBINDINGS.md's Terminal table" "$(documented_keys)" || rc=1

compare_keys "AeroSpace's main binding mode" "$(aerospace_configured_keys '[mode.main.binding]')" \
  "KEYBINDINGS.md's AeroSpace table" "$(aerospace_documented_keys)" || rc=1

compare_keys "AeroSpace's service binding mode" "$(aerospace_configured_keys '[mode.service.binding]')" \
  "KEYBINDINGS.md's Service mode table" "$(aerospace_service_documented_keys)" || rc=1

compare_keys ".tmux.conf's prefix table" "$(tmux_configured_keys prefix)" \
  "KEYBINDINGS.md's tmux With prefix table" "$(tmux_prefix_documented_keys)" || rc=1

compare_keys ".tmux.conf's copy-mode-vi table" "$(tmux_configured_keys copy-mode-vi)" \
  "KEYBINDINGS.md's tmux Copy mode table" "$(tmux_copy_mode_documented_keys)" || rc=1

# One direction only: the rest of that table is macOS built-in, which no
# config here binds, as its Source line declares.
compare_config_to_doc "Hammerspoon" "$(hammerspoon_configured_keys)" \
  "KEYBINDINGS.md's Text editing table" "$(text_editing_documented_keys)" || rc=1

compare_keys ".zshrc's bindkey" "$(zsh_configured_keys)" \
  "KEYBINDINGS.md's zsh table" "$(zsh_documented_keys)" \
  "$(printf '%s\n' "${ZSH_BOUND_ELSEWHERE[@]}")" || rc=1

# These two readers exit non-zero, with their own message, on a config they
# cannot read; a status inside a "$(...)" argument is dropped, so take it from
# an assignment.
abbr_words="$(abbr_configured_words)" || rc=1
compare_keys "abbr.zsh's ABBR_MAP" "$abbr_words" \
  "KEYBINDINGS.md's Abbreviations table" "$(abbr_documented_words)" || rc=1

nvim_keys="$(nvim_configured_leader_keys)" || rc=1
compare_keys "config/nvim's keymaps" "$nvim_keys" \
  "KEYBINDINGS.md's Neovim section" "$(nvim_documented_leader_keys)" \
  "$(printf '%s\n' "${NVIM_LEADER_BOUND_ELSEWHERE[@]}")" || rc=1

exit "$rc"
