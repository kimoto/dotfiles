#!/bin/sh
# Register (default) or remove (--uninstall) the Claude Code → tmux hooks in
# ~/.claude/settings.json: the agent-state hook (config/tmux-agent-status),
# and the handler that keeps a hunk pane on the repo Claude is in.
# How the merge stays safe: bin/claude_settings_lib.sh. rmworld.sh runs --uninstall.
set -eu

# shellcheck source=bin/claude_settings_lib.sh
. "$(dirname "$(readlink -f "$0")")/claude_settings_lib.sh"

# Unexpanded on purpose ($HOME resolves per machine at hook runtime); the -x
# guard keeps the hook a no-op when ~/bin is gone instead of erroring.
# shellcheck disable=SC2016
HOOK='"$HOME/.config/tmux-agent-status/scripts/hook.sh"'
GUARDED="[ ! -x $HOOK ] || $HOOK"
# shellcheck disable=SC2016
GUARDED_HUNK='[ ! -x "$HOME/bin/claude_tmux_hunk.sh" ] || "$HOME/bin/claude_tmux_hunk.sh"'

settings_open "$@"

# Also strips the state hook's old name, bin/claude_tmux_indicator.sh.
STRIP=$(strip_def strip_indicator 'contains("tmux-agent-status/")
  or contains("claude_tmux_indicator.sh") or contains("claude_tmux_hunk.sh")')

if [ "$MODE" = "--uninstall" ]; then
  jq "$STRIP strip_indicator" "$SETTINGS" >"$tmp"
else
  jq --arg cmd "$GUARDED" --arg hunk "$GUARDED_HUNK" "$STRIP"'
    # hook.sh maps each event to a state; this list only says which events.
    def ensure($event):
      .hooks[$event] += [{hooks: [{type: "command", command: ($cmd + " " + $event)}]}];
    strip_indicator
    | ensure("Notification")      # permission prompt / idle -> waiting
    | ensure("Stop")              # finished responding -> done
    | ensure("UserPromptSubmit")
    | ensure("PreToolUse")        # fires before any permission prompt
    | ensure("PostToolUse")       # clears the red an approved prompt left
    | ensure("SessionStart")
    | ensure("SessionEnd")
    # EnterWorktree/ExitWorktree move Claude without firing CwdChanged; a `cd`
    # in Bash fires only CwdChanged. Both are needed to follow every move.
    | .hooks.PostToolUse += [{matcher: "EnterWorktree|ExitWorktree",
                              hooks: [{type: "command", command: $hunk}]}]
    | .hooks.CwdChanged += [{hooks: [{type: "command", command: $hunk}]}]
  ' "$SETTINGS" >"$tmp"
fi

settings_commit "tmux hooks"
