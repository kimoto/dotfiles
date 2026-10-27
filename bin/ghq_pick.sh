#!/bin/sh
# Pick a ghq-cloned repo with fzf and print its absolute path: `g` cds there,
# tmux's prefix + G goes to a window there. Repos zoxide has seen come first,
# most visited on top, so the usual ones need no typing; visits to a repo's
# subdirectories and worktrees count toward the repo.
#
#   ghq_pick.sh [query]   pick; prints nothing and exits non-zero on abort
#   ghq_pick.sh --list    the ranked list only
set -eu

root=$(ghq root)

ranked() {
	# Through the environment: BSD awk refuses a newline in a -v value.
	GHQ_PICK_LIST=$(ghq list) && export GHQ_PICK_LIST
	{ zoxide query -ls 2>/dev/null || true; } |
		awk -v root="$root/" '
			BEGIN { n = split(ENVIRON["GHQ_PICK_LIST"], order, "\n"); for (i = 1; i <= n; i++) repo[order[i]] = 1 }
			index($0, root) {
				score = $1
				rel = $0
				sub(/^ *[0-9.]+ /, "", rel)
				if (index(rel, root) != 1) next
				rel = substr(rel, length(root) + 1)
				while (rel != "" && !(rel in repo))
					if (!sub(/\/[^\/]*$/, "", rel)) rel = ""
				if (rel != "") total[rel] += score
			}
			END { for (i = 1; i <= n; i++) if (order[i] != "") printf "%s\t%d\t%s\n", total[order[i]] + 0, i, order[i] }
		' |
		sort -t "$(printf '\t')" -k1,1gr -k2,2n |
		cut -f3
}

if [ "${1:-}" = --list ]; then
	ranked
	exit 0
fi

# --tiebreak=index: among equally good matches, the ranked order decides.
# --layout=reverse matches FZF_DEFAULT_OPTS, which a tmux popup does not inherit.
# The preview runs under sh: $SHELL is zsh, which aborts on a repo with no
# README instead of falling through to the listing.
preview="for f in '$root'/{}/README*; do
	[ -e \"\$f\" ] && exec bat --style=plain --color=always \"\$f\"
done
ls '$root'/{}"
sel=$(ranked | fzf --tiebreak=index --layout=reverse --query="$*" --with-shell 'sh -c' --preview "$preview")
printf '%s/%s\n' "$root" "$sel"
