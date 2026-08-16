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

# Claude Code のユーザールール。~/.claude/rules/ は conf.d で、配下の .md が
# 全セッションに読み込まれる。各リポジトリが自分の分だけを張るので、会社用の
# 非公開リポジトリが rules/company を並べても衝突しない。
# ~/.claude itself is never linked: it also holds runtime state (transcripts,
# sessions, plugin caches). Only our own entry is linked, so a private work
# repo can drop its rules alongside without this public repo ever seeing them.
mkdir -p ./.claude/rules
ln -nsf "$BASE_DIR/claudecode/rules" ./.claude/rules/dotfiles
