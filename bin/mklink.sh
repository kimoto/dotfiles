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

# Claude Code user rules. ~/.claude/rules/ is a conf.d: every .md under it
# loads into every session. Each source repo links its own subdirectory, so
# another repo can keep its rules there too — only our own entry is linked.
# ~/.claude itself is never linked: it also holds runtime state (transcripts,
# sessions, plugin caches).
mkdir -p ./.claude/rules
ln -nsf "$BASE_DIR/claudecode/rules" ./.claude/rules/dotfiles

# Claude Code user skills. Unlike rules/, ~/.claude/skills/ also holds skills
# installed by other tools, so each of ours is linked by name — never the
# directory. Adding one means a line here and in bin/rmworld.sh (a test fails
# if the two lists drift).
mkdir -p ./.claude/skills
ln -nsf "$BASE_DIR/claudecode/skills/session-resume" ./.claude/skills/session-resume
ln -nsf "$BASE_DIR/claudecode/skills/wrapup" ./.claude/skills/wrapup
