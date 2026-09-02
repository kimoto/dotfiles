#!/bin/sh
# Claude Code のルールとスキルを ~/.claude に張る (mklink.sh から切り出し)。
# Link this repo's Claude Code rules and skills into ~/.claude.
#
# Split out of bin/mklink.sh so a Claude Code cloud environment's setup script
# can run this part alone. A cloud session's $HOME belongs to the platform —
# git identity, credentials, shell config — and mklink.sh would replace
# ~/.gitconfig along with everything else. Nothing here is written outside
# ~/.claude, and a test holds that line.
#
# ~/.claude itself is never linked: it also holds runtime state (transcripts,
# sessions, plugin caches).

set -eu

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.."; pwd)

cd "$HOME" || exit 1

# Claude Code user rules. ~/.claude/rules/ is a conf.d: every .md under it
# loads into every session. Each source repo links its own subdirectory, so
# another repo can keep its rules there too — only our own entry is linked.
mkdir -p ./.claude/rules
ln -nsf "$BASE_DIR/claudecode/rules" ./.claude/rules/dotfiles

# Claude Code user skills. Unlike rules/, ~/.claude/skills/ also holds skills
# installed by other tools, so each of ours is linked by name — never the
# directory. Adding one means a line here and in bin/rmworld.sh (a test fails
# if the two lists drift).
mkdir -p ./.claude/skills
ln -nsf "$BASE_DIR/claudecode/skills/session-resume" ./.claude/skills/session-resume
ln -nsf "$BASE_DIR/claudecode/skills/wrapup" ./.claude/skills/wrapup
