#!/bin/sh
# 注意: このスクリプトは mklink.sh が $HOME に張ったシンボリックリンクを外します。
# Notice: removes the symlinks created by mklink.sh from $HOME.
#
# mklink.sh と対になっているので、リンク対象を増減したら両方を更新すること。
# Keep this list in sync with bin/mklink.sh.

set -eu

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.."; pwd)

cd "$HOME" || exit 1

# Claude Code のフック登録も外す (mkworld.sh の install と対)。
# Unregister the Claude Code tmux-indicator hooks (pairs with mkworld.sh).
sh "$BASE_DIR/bin/install_claude_tmux_hooks.sh" --uninstall || true

# このリポジトリを指すシンボリックリンクのときだけ外す (実ファイルは消さない)。
# Only remove the entry if it is a symlink (never touch real files).
unlink_if_symlink() {
    if [ -L "$1" ]; then
        rm "$1"
        echo "removed symlink: $1"
    fi
}

# ディレクトリリンク (mklink.sh と同じ並び)
unlink_if_symlink "./bin"
unlink_if_symlink "./.config"
unlink_if_symlink "./.hammerspoon"
unlink_if_symlink "./.mysqlsh"
unlink_if_symlink "./.vim"

# ファイルリンク (mklink.sh と同じ並び)
unlink_if_symlink "./.inputrc"
unlink_if_symlink "./.editrc"
unlink_if_symlink "./.gitconfig"
unlink_if_symlink "./.gitconfig.default_user"
unlink_if_symlink "./.gitignore"
unlink_if_symlink "./.tmux.conf"
unlink_if_symlink "./.zshrc"
unlink_if_symlink "./.irbrc"
unlink_if_symlink "./.vimrc"
unlink_if_symlink "./.aerospace.toml"
