#!/bin/bash

# Keybinding cheatsheet picker: fzf over every table in KEYBINDINGS.md.
#
# which-key, but for the layers a terminal actually stacks (macOS -> AeroSpace
# -> Ghostty -> tmux -> zsh -> nvim). Each row is prefixed with the layer (and
# subsection) it belongs to, so a query narrows to one layer — `tmux` for the
# tmux binds, `prefix` for just the prefix table — and erasing it widens back
# out to everything. That prefix is also what makes the list unambiguous: three
# layers bind `f`, and only the `[...]` tag says which one you are looking at.
#
# One script, one caller: zsh's `keys` helper and the ⌃+X ? widget (.zshrc).
# tmux's prefix + ? opens tmux-which-key's own menu tree instead (.tmux.conf),
# not this script.
#
# Usage: keys.sh [--list] [query...]
#   --list   print the rows and exit, no picker (tests, and for piping to grep)
#   query    seeds the fzf query (e.g. `keys.sh tmux`)
#
# Env: KEYBINDINGS_MD overrides the document, KEYS_FZF_HEIGHT the fzf height
# (the tmux popup sets 100%; the zsh widget keeps the default so the command
# line being edited stays visible above the list).

set -euo pipefail

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.." || exit 1; pwd)
DOC="${KEYBINDINGS_MD:-$BASE_DIR/KEYBINDINGS.md}"

list_only=0
if [ "${1:-}" = "--list" ]; then
    list_only=1
    shift
fi

if [ ! -f "$DOC" ]; then
    echo "keys: no such keybinding reference: $DOC" >&2
    exit 1
fi

# Markdown -> "[layer / subsection] key | action" rows. `## ` opens a layer and
# clears any subsection (otherwise the first table of a new layer would inherit
# the last `###` of the previous one); `### ` refines it. Table scaffolding —
# the |---| separator and the header row of each of the three table shapes the
# document uses (Key/Command/Word) — is dropped: unselectable noise in a picker.
extract() {
    awk '
        /^## /  { layer = substr($0, 4); section = ""; next }
        /^### / { section = substr($0, 5); next }
        /^\|/ {
            if ($0 ~ /^[|[:space:]:-]+$/) next
            if ($0 ~ /^\|[[:space:]]*(Key|Command|Word)[[:space:]]*\|/) next
            row = $0
            sub(/^\|[[:space:]]*/, "", row)
            sub(/[[:space:]]*\|[[:space:]]*$/, "", row)
            context = layer
            if (section != "") context = context " / " section
            printf "[%s] %s\n", context, row
        }
    ' "$DOC"
}

if [ "$list_only" -eq 1 ]; then
    extract
    exit 0
fi

# --no-exit-0 because FZF_DEFAULT_OPTS carries --exit-0: a lookup that closes
# itself the moment the query matches nothing is the one case where you most
# want to see the list and fix the query.
extract | fzf \
    --no-exit-0 \
    --no-multi \
    --layout=reverse \
    --height="${KEYS_FZF_HEIGHT:-60%}" \
    --prompt='keys> ' \
    --header='keybindings: type a layer (tmux / zsh / nvim / ghostty) to narrow' \
    --query="$*"
