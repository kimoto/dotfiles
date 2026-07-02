#!/bin/sh
# Register the Claude Code → tmux state-indicator hooks in
# ~/.claude/settings.json (user level, so every project gets them). jq-merges
# into the existing file: unrelated settings and hooks are preserved, and
# reruns are no-ops (idempotent). Called by bin/mkworld.sh; safe to rerun by
# hand. Never fails the bootstrap — missing jq or a hand-broken settings.json
# only warns and exits 0.
set -eu

SETTINGS_DIR="$HOME/.claude"
SETTINGS="$SETTINGS_DIR/settings.json"
# Kept unexpanded on purpose: the hook command is run through a shell, so
# $HOME resolves per machine and settings.json stays portable. ~/bin is the
# symlink mklink.sh creates.
# shellcheck disable=SC2016
INDICATOR='$HOME/bin/claude_tmux_indicator.sh'

if ! command -v jq >/dev/null 2>&1; then
  echo "install_claude_tmux_hooks: jq not found; skipping" >&2
  exit 0
fi

mkdir -p "$SETTINGS_DIR"
[ -f "$SETTINGS" ] || printf '{}\n' >"$SETTINGS"

if ! jq empty "$SETTINGS" 2>/dev/null; then
  echo "install_claude_tmux_hooks: $SETTINGS is invalid JSON; leaving it untouched" >&2
  exit 0
fi

tmp="$(mktemp)"
jq --arg ind "$INDICATOR" '
  # Append {type: command, command: $cmd} under .hooks[$event] unless an entry
  # already runs exactly that command.
  def ensure($event; $cmd):
    .hooks[$event] = ((.hooks[$event] // [])
      | if any(.[]; any(.hooks[]?; .command == $cmd)) then .
        else . + [{hooks: [{type: "command", command: $cmd}]}] end);
  ensure("Notification";       $ind + " waiting")  # permission prompt / idle
  | ensure("Stop";             $ind + " done")     # finished responding
  | ensure("UserPromptSubmit"; $ind + " clear")
  | ensure("PreToolUse";       $ind + " clear")    # resumed after a permission grant
  | ensure("SessionStart";     $ind + " clear")
  | ensure("SessionEnd";       $ind + " clear")
' "$SETTINGS" >"$tmp"
mv "$tmp" "$SETTINGS"
echo "install_claude_tmux_hooks: indicator hooks present in $SETTINGS"
