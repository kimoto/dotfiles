#!/bin/bash
# Bootstrap this machine by climbing the phases in docs/staged-bootstrap.md:
# minimal -> basic -> standard -> extra -> platform. A phase that cannot be reached (no zsh,
# no sudo for Homebrew, a failed `brew bundle`) ends the climb there instead of
# the whole run: the phases below it already work on their own, so the machine
# is left usable one step down. The last line names the phase reached and why
# the climb stopped.
#
# Exit status is 0 whenever minimal was reached. MKWORLD_EXPECT=<phase> turns a
# lower result into exit 1, for callers (CI) that know how far they should get.

set -euo pipefail
set -x

BASE_DIR=$(cd "$(dirname "$(readlink -f "$0")")/.."; pwd)

PHASES=(minimal basic standard extra platform)
phase_rank() {
    local i
    for i in "${!PHASES[@]}"; do
        [ "${PHASES[$i]}" = "$1" ] && { echo "$i"; return; }
    done
    echo "mkworld: unknown phase: $1" >&2
    exit 2
}
# Fail on a typo before doing any work, not after a Homebrew install.
[ -z "${MKWORLD_EXPECT:-}" ] || phase_rank "$MKWORLD_EXPECT" >/dev/null

reached=""
stopped=""
stop() { stopped="$1"; echo "mkworld: stopping at $reached: $1" >&2; }

load_brew() {
    if [ -x "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi
}

cd "$HOME"

# Helpers are executed directly, never as `sh <script>`: each one's shebang
# picks its interpreter. `sh` would be bash-in-POSIX-mode on macOS but dash on
# Linux, and setup_homebrew.sh (and friends) open with `set -euo pipefail`,
# which dash rejects outright.
climb() {
    # minimal: the OS's bash, vim and git. The links are the one step whose
    # failure is fatal, since nothing below works without them.
    mkdir -p ./tmp
    "$BASE_DIR/bin/mklink.sh"
    reached=minimal

    # basic: the OS's zsh, plus what a git clone brings. NeoBundle is a
    # submodule under .vim/bundle/; with it present, the first `vim` launch runs
    # NeoBundleCheck instead of erroring on every NeoBundle command.
    if ! command -v zsh >/dev/null 2>&1; then
        stop "zsh not installed"; return
    fi
    if ! git -C "$BASE_DIR" submodule update --init --recursive; then
        stop "git submodule update failed"; return
    fi
    reached=basic

    # standard: Homebrew and Brewfile.standard.
    # SKIP_BREW=1 means the caller already installed them; that is checked
    # below like any other install.
    if [ "${SKIP_BREW:-0}" = "0" ]; then
        if ! SKIP_BREWFILE_EXTRA=1 "$BASE_DIR/bin/setup_homebrew.sh"; then
            stop "Homebrew or Brewfile.standard failed to install"; return
        fi
    fi
    load_brew
    if ! command -v brew >/dev/null 2>&1; then
        stop "brew not installed"; return
    fi
    if ! brew bundle check --file="$BASE_DIR/Brewfile.standard"; then
        stop "Brewfile.standard not satisfied"; return
    fi
    reached=standard

    # extra: Brewfile.extra, tools that only run when typed. SKIP_BREWFILE_EXTRA=1
    # leaves it and the platform Brewfile to the caller too.
    bundle_phase Brewfile.extra || return 0
    reached=extra

    # platform: what only this OS gets, and the likeliest to fail (GUI casks,
    # system settings that need sudo), hence last.
    case "$(uname)" in
        Darwin)
            bundle_phase Brewfile.macos || return 0
            # System preferences: Finder, key repeat, startup mute (sudo for nvram).
            if ! "$BASE_DIR/bin/setup_macosx.sh"; then
                stop "setup_macosx.sh failed"; return
            fi
            ;;
        Linux)
            bundle_phase Brewfile.linux || return 0
            ;;
    esac
    reached=platform
}

# Install (unless the caller did) and check one Brewfile; a miss ends the climb.
bundle_phase() {
    if [ "${SKIP_BREW:-0}" = "0" ] && [ "${SKIP_BREWFILE_EXTRA:-0}" != "1" ]; then
        if ! brew bundle install --file="$BASE_DIR/$1"; then
            stop "$1 failed to install"; return 1
        fi
    fi
    if ! brew bundle check --file="$BASE_DIR/$1"; then
        stop "$1 not satisfied"; return 1
    fi
}

climb
load_brew

# What follows is not a phase: each step runs when its own tool is present,
# whatever phase was reached, and a failure only warns. CI installs tmux without
# the rest of Brewfile.extra and still needs the tmux plugins.

# tpm and its plugins, headlessly (idempotent).
if command -v tmux >/dev/null 2>&1; then
    "$BASE_DIR/bin/install_tmux_plugins.sh" || echo "tmux plugin install failed" >&2
else
    echo "tmux not found on PATH; skipping tmux plugin install" >&2
fi

# Claude Code: the tmux state-indicator and idle hooks, and the settings meant
# to match on every machine (claudecode/settings-shared.json). Each one skips
# with a warning when jq is missing.
"$BASE_DIR/bin/install_claude_tmux_hooks.sh" || echo "Claude tmux hooks failed" >&2
"$BASE_DIR/bin/install_claude_idle_hooks.sh" || echo "Claude idle hooks failed" >&2
"$BASE_DIR/bin/install_claude_settings.sh" --sync || echo "Claude settings sync failed" >&2

# The check toolchain pinned in mise.toml, before the hooks below that run it.
# Each bin/lint_*.sh names the tool that is missing.
if command -v mise >/dev/null 2>&1; then
    (cd "$BASE_DIR" && mise trust --quiet mise.toml && mise install) \
        || echo "mise install failed; the git hooks will refuse commits until it succeeds" >&2
fi

# Git hooks (lefthook) and the commit message template.
if command -v lefthook >/dev/null 2>&1; then
    (cd "$BASE_DIR" && lefthook install && git config --local commit.template .gitmessage) \
        || echo "lefthook install failed" >&2
fi

# macOS: daily background install/upgrade of homebrew/core formulae (casks and
# third-party taps stay manual).
if [ "$(uname)" = "Darwin" ] && [ "${SKIP_BREW:-0}" = "0" ] && command -v brew >/dev/null 2>&1; then
    "$BASE_DIR/bin/setup_brew_auto_upgrade.sh" || true
fi

set +x
echo "mkworld: reached $reached${stopped:+ (stopped: $stopped)}"
if [ -n "${MKWORLD_EXPECT:-}" ] && [ "$(phase_rank "$reached")" -lt "$(phase_rank "$MKWORLD_EXPECT")" ]; then
    echo "mkworld: expected to reach $MKWORLD_EXPECT" >&2
    exit 1
fi
