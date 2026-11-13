#!/bin/sh
# Loads the plugins in @tpm_plugins the way tpm's `run` does, but mostly as two
# chains at once, and returns only when all are done. Each plugin is a script
# that calls `tmux` once per option or key, and each of those calls is a process
# start (5-9 ms on macOS); in one chain they added up past a second.
# Still synchronous on purpose: continuum's restore and the plugins' writes to
# ~/.claude/settings.json race anything that keeps loading after the config.
# tpm stays installed and @tpm_plugins stays the list, because tpm's install,
# update and clean read it. `set -g @plugin` lines are not read here.

# What tpm sets up besides loading: its path, kept when already set (the
# installer and the tests point it elsewhere), and its three bindings.
if [ -n "${TMUX_PLUGIN_MANAGER_PATH:-}" ]; then
  dir="${TMUX_PLUGIN_MANAGER_PATH%/}"
else
  dir="$HOME/.tmux/plugins"
  tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH "$dir/"
fi
tmux bind-key I run-shell "$dir/tpm/bindings/install_plugins" \; \
  bind-key U run-shell "$dir/tpm/bindings/update_plugins" \; \
  bind-key M-u run-shell "$dir/tpm/bindings/clean_plugins"

# load NAME...: run each named plugin's *.tmux in order, as tpm does: output
# dropped, a missing plugin skipped, a failing one ignored. Always succeeds, so
# a plugin not installed yet never reads as a config error.
load() {
  for name in "$@"; do
    for f in "$dir/$name/"*.tmux; do
      [ -f "$f" ] || continue
      "$f" >/dev/null 2>&1
    done
  done
  return 0
}

# resurrect and assistant-resurrect read each other's options, so they keep
# their order in a chain of their own. The rest only bind keys and set their
# own options; they keep the list's order in the other chain.
# continuum loads alone once both are done: it decides whether to restore and
# autosave by counting the processes named tmux, and counts any `tmux` call
# still running as another server, then silently does neither. menus comes
# after it, as in the list, because it keeps initializing in the background
# after it returns, out of reach of `wait`.
restore_chain=''
rest_chain=''
tail_chain=''
for spec in $(tmux show-option -gqv @tpm_plugins); do
  name="${spec%%#*}"
  name="${name##*/}"
  name="${name%.git}"
  case "$name" in
    tpm) ;;
    tmux-continuum | tmux-menus) tail_chain="$tail_chain $name" ;;
    tmux-resurrect | tmux-assistant-resurrect)
      restore_chain="$restore_chain $name" ;;
    *) rest_chain="$rest_chain $name" ;;
  esac
done

# shellcheck disable=SC2086 # the chains are space-separated plugin names
load $restore_chain &
# shellcheck disable=SC2086
load $rest_chain
wait
# shellcheck disable=SC2086
load $tail_chain
