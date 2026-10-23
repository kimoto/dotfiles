#!/bin/sh
# git merge driver (.gitconfig, routed by config/git/attributes): a
# syntax-aware three-way merge with mergiraf, so two edits to different parts
# of one line or call stop being a conflict.
#
# Without mergiraf (it is only in Brewfile.extra) git's own line merge runs
# instead, in the zdiff3 style .gitconfig sets, so a machine that lacks it
# merges exactly as before. Either way the result lands in the current
# version's file and the exit status is non-zero when conflicts remain.
#
# Arguments, in the order .gitconfig passes them: base, current, other,
# conflict marker size, final path, then the three labels.

base=$1 current=$2 other=$3 size=$4 path=$5
base_label=$6 current_label=$7 other_label=$8

if command -v mergiraf >/dev/null 2>&1; then
  exec mergiraf merge --git "$base" "$current" "$other" -l "$size" -p "$path" \
    -s "$base_label" -x "$current_label" -y "$other_label"
fi
exec git merge-file --zdiff3 --marker-size="$size" \
  -L "$current_label" -L "$base_label" -L "$other_label" "$current" "$base" "$other"
