#!/bin/bash

# Render KEYBINDINGS.md with the recently added bindings marked, so the keys not
# learned yet stand out in the place already used to look keys up (prefix + ?).
#
# "Recently added" is decided per key — the first cell of a table row — from the
# commit that first introduced that key string, not from which lines a diff
# happens to touch: rewording a description or moving a row between sections
# must not make a years-old binding look new. A key absent from the history
# entirely (a row added on the current branch) counts as new.
#
# The history walk costs a few seconds, so the marked copy is cached under
# $XDG_CACHE_HOME/dotfiles and rebuilt only when KEYBINDINGS.md or the window
# changes. Prints the path to the marked file; --print dumps it to stdout.

set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
SOURCE="$BASE_DIR/KEYBINDINGS.md"
MARKER="🆕"

days=14
force=0
print=0
page=0

usage() {
  cat <<'EOF'
Usage: keybindings_new.sh [--days N] [--force] [--print]

Print the path to a copy of KEYBINDINGS.md whose recently added keys are
marked. With --print, write that copy to stdout instead.

  --days N   how recent counts as new (default 14)
  --force    rebuild even when the cache is current
  --print    write the marked document to stdout
  --page     show it in a pager (glow when installed, otherwise less)
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --days) days="${2:-}"; shift 2 || true ;;
    --force) force=1; shift ;;
    --print) print=1; shift ;;
    --page) page=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$days" in
  '' | *[!0-9]*) echo "--days needs a number, got '${days}'" >&2; exit 2 ;;
esac

[ -f "$SOURCE" ] || { echo "x KEYBINDINGS.md not found at $SOURCE" >&2; exit 1; }

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
mkdir -p "$cache_dir"
marked="$cache_dir/KEYBINDINGS.marked.md"
stamp="$cache_dir/KEYBINDINGS.marked.stamp"

# The cache is keyed on the document and the window, so editing either rebuilds
# it without anyone remembering to pass --force.
want="$(cksum <"$SOURCE" | awk '{print $1 "-" $2}')-$days"
# glow renders the tables and makes the marker stand out; less keeps the popup
# usable on a machine that only has Brewfile.basic installed (CI included).
emit() {
  if [ "$page" -eq 1 ]; then
    if command -v glow >/dev/null 2>&1; then
      glow -p "$marked"
    else
      less -R "$marked"
    fi
  elif [ "$print" -eq 1 ]; then
    cat "$marked"
  else
    echo "$marked"
  fi
}

if [ "$force" -eq 0 ] && [ -f "$marked" ] && [ "$(cat "$stamp" 2>/dev/null || true)" = "$want" ]; then
  emit
  exit 0
fi

cd "$BASE_DIR"

# Prefer origin/main: this checkout is shared with other sessions, so HEAD may
# be sitting on someone else's branch and its history is not the shared one.
range=origin/main
git rev-parse --verify --quiet "$range" >/dev/null || range=HEAD

# macOS ships bash 3.2 (no associative arrays), so the key -> first-seen map and
# the rendering both live in awk.
first_seen="$cache_dir/KEYBINDINGS.firstseen.tmp"
git log --reverse --format='@@commit@@ %ct' -p "$range" -- KEYBINDINGS.md 2>/dev/null |
  awk '
    /^@@commit@@ / { ts = $2; next }
    /^\+\|/ {
      line = substr($0, 3)                       # drop the diff "+|"
      idx = index(line, "|")
      if (idx == 0) next
      cell = substr(line, 1, idx - 1)
      gsub(/^[ \t]+|[ \t]+$/, "", cell)
      if (cell == "" || cell ~ /^[-: ]+$/) next  # separator row
      if (!(cell in seen)) { seen[cell] = 1; printf "%s\t%s\n", ts, cell }
    }
  ' >"$first_seen"

now="$(date +%s)"
cutoff=$((now - days * 86400))

awk -v cutoff="$cutoff" -v marker="$MARKER" -v mapfile="$first_seen" '
  BEGIN {
    while ((getline line < mapfile) > 0) {
      tab = index(line, "\t")
      if (tab) first[substr(line, tab + 1)] = substr(line, 1, tab - 1)
    }
  }
  { rows[NR] = $0 }
  END {
    for (i = 1; i <= NR; i++) {
      line = rows[i]
      nextline = (i < NR) ? rows[i + 1] : ""
      # Only table rows are candidates, and a header row is always the one
      # directly above the |---|---| separator — never mark it.
      if (line !~ /^\| / || nextline ~ /^\|[-: ]+\|/) { print line; continue }
      idx = index(substr(line, 2), "|")
      if (idx == 0) { print line; continue }
      cell = substr(line, 2, idx - 1)
      gsub(/^[ \t]+|[ \t]+$/, "", cell)
      if (cell == "" || cell ~ /^[-: ]+$/) { print line; continue }
      if (!(cell in first) || first[cell] >= cutoff)
        print "| " marker " " substr(line, 3)
      else
        print line
    }
  }
' "$SOURCE" >"$marked.tmp"

mv "$marked.tmp" "$marked"
rm -f "$first_seen"
printf '%s' "$want" >"$stamp"

emit
