#!/bin/sh

set -eu
set -x

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.."; pwd)

cd "$HOME"
ln -nsf "$BASE_DIR/bin/" ./bin
if [ -d "$HOME/.config" ] && [ ! -L "$HOME/.config" ]; then
    backup_path="$HOME/.config.bak.$(date +%Y%m%d%H%M%S)"
    mv "$HOME/.config" "$backup_path"
fi
ln -nsf "$BASE_DIR/config" ./.config
ln -nsf "$BASE_DIR/hammerspoon" ./.hammerspoon
ln -nsf "$BASE_DIR/mysqlsh" ./.mysqlsh
ln -nsf "$BASE_DIR/.vim" ./.vim

ln -sf "$BASE_DIR/.inputrc" ./
ln -sf "$BASE_DIR/.editrc" ./
ln -sf "$BASE_DIR/.bashrc" ./
ln -sf "$BASE_DIR/.gdbinit" ./
ln -sf "$BASE_DIR/.gitconfig" ./
ln -sf "$BASE_DIR/.gitconfig.default_user" ./
ln -sf "$BASE_DIR/.gitignore" ./
ln -sf "$BASE_DIR/.gitmessage" ./
ln -sf "$BASE_DIR/.tmux.conf" ./
ln -sf "$BASE_DIR/.zshrc" ./
ln -sf "$BASE_DIR/.irbrc" ./
ln -sf "$BASE_DIR/.vimrc" ./
ln -sf "$BASE_DIR/.aerospace.toml" ./

# Codex keeps machine-specific settings and runtime state in ~/.codex.
# Preserve existing configs; only a missing config gets our shared defaults.
mkdir -p ./.codex
if [ ! -e ./.codex/config.toml ] && [ ! -L ./.codex/config.toml ]; then
    ln -s "$BASE_DIR/codex/config.toml" ./.codex/config.toml
elif [ "$(readlink -f ./.codex/config.toml)" != "$BASE_DIR/codex/config.toml" ]; then
    echo "Preserving existing Codex config; merge defaults from $BASE_DIR/codex/config.toml" >&2
fi

# Share Claude user guidance without replacing an existing Codex instruction file.
if [ ! -e ./.codex/AGENTS.md ] && [ ! -L ./.codex/AGENTS.md ]; then
    ln -s "$BASE_DIR/codex/AGENTS.md" ./.codex/AGENTS.md
elif [ "$(readlink -f ./.codex/AGENTS.md)" != "$BASE_DIR/codex/AGENTS.md" ]; then
    echo "Preserving existing Codex instructions; merge $BASE_DIR/codex/AGENTS.md" >&2
fi

# Claude Code user rules. ~/.claude/rules/ is a conf.d: every .md under it
# loads into every session. Each source repo links its own subdirectory, so
# another repo can keep its rules there too — only our own entry is linked.
# ~/.claude itself is never linked: it also holds runtime state (transcripts,
# sessions, plugin caches).
mkdir -p ./.claude/rules
ln -nsf "$BASE_DIR/claudecode/rules" ./.claude/rules/dotfiles

# claudecode/rules-cloud describes what a container lacks, so every line of it
# is false on the machine this script is setting up. bin/link_claude_dir.sh
# --cloud is the only thing that puts it here, and the only other thing that
# knows the name, so a $HOME that was once a container keeps it until here.
if [ -L ./.claude/rules/dotfiles-cloud ]; then
    rm -f ./.claude/rules/dotfiles-cloud
fi

# Only while it still points here: that path holds this machine's own settings.
if [ "$(readlink -f ./.claude/settings.json 2>/dev/null)" = "$BASE_DIR/claudecode/settings-cloud.json" ]; then
    rm -f ./.claude/settings.json
fi

# Claude Code user skills. Unlike rules/, ~/.claude/skills/ also holds skills
# installed by other tools, so each of ours is linked by name — never the
# directory. Adding one means a line here and in bin/rmworld.sh (a test fails
# if the two lists drift).
mkdir -p ./.claude/skills
ln -nsf "$BASE_DIR/claudecode/skills/session-resume" ./.claude/skills/session-resume
ln -nsf "$BASE_DIR/claudecode/skills/wrapup" ./.claude/skills/wrapup
