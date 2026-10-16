#!/bin/bash
# The two lowest phases of the setup, right after a clone and mklink.sh:
# minimal (bash and vim from the OS) and basic (adds zsh, still no extra
# binary such as eza, bat, starship or sheldon). Both shells must start clean
# and the everyday commands, git included, must still work, without tmux.
#
# ci_zsh_loading_test.sh cannot cover this: its "basic" set already brings the
# rich tools, so a .zshrc that only works with them still passes there.
set -euo pipefail

die() { echo "CI error: $*" >&2; exit 1; }

REPO="$(cd "$(dirname "$0")/.." && pwd)"

# The test means nothing if a rich tool is on PATH: the fallback paths it guards
# would never run.
for t in eza bat starship sheldon zoxide; do
  if command -v "$t" >/dev/null 2>&1; then
    die "$t is on PATH; run this where only the distro shells are installed"
  fi
done
command -v zsh >/dev/null 2>&1 || die "zsh not installed"
command -v script >/dev/null 2>&1 || die "script (util-linux) not installed"

HOME_DIR="$(mktemp -d)"
trap 'rm -rf "$HOME_DIR"' EXIT
HOME="$HOME_DIR" "$REPO/bin/mklink.sh" >/dev/null 2>&1 || die "mklink.sh failed"

# What a login on this machine sees: no CI markers, no agent, a real terminal.
run_in_pty() {
  env -i HOME="$HOME_DIR" PATH="$PATH" TERM=xterm-256color LANG=C.UTF-8 \
    DOTFILES_NO_SYNC_CHECK=1 DOTFILES_NO_BREW_CHECK=1 DOTFILES_NO_MISE_CHECK=1 \
    script -q -e -c "$1" /dev/null </dev/null 2>&1
}

errors='command not found|not found:|No such file|no such file|parse error|syntax error'

check() {
  local label="$1" out="$2"; shift 2
  printf '== %s ==\n%s\n' "$label" "$out"
  if printf '%s\n' "$out" | grep -E "$errors"; then
    die "$label printed an error"
  fi
  local want
  for want in "$@"; do
    printf '%s\n' "$out" | grep -q "$want" || die "$label: missing $want"
  done
}

# git reads ~/.gitconfig from bash too, so its pager and editor must exist here.
cat >"$HOME_DIR/probe.bash" <<'PROBE'
ls / >/dev/null && echo BASH_LS_OK
printf 'git body\n' | LESS=-FX sh -c "$(git config core.pager)" | grep -q 'git body' && echo BASH_GIT_PAGER_OK
command -v "$(git var GIT_EDITOR)" >/dev/null && echo BASH_GIT_EDITOR_OK
PROBE
bash_out="$(run_in_pty "bash -i -c 'source $HOME_DIR/probe.bash'")"
check "bash -i" "$bash_out" BASH_LS_OK BASH_GIT_PAGER_OK BASH_GIT_EDITOR_OK

# Each probe prints a marker only when the command it names really worked.
probe="$HOME_DIR/probe.zsh"
cat >"$probe" <<'PROBE'
cd /
ls >/dev/null && print ZSH_LS_OK
ll >/dev/null && print ZSH_LL_OK
l >/dev/null && print ZSH_L_OK
print -r -- 'man body' | eval "${MANPAGER:-cat}" | grep -q 'man body' && print ZSH_MANPAGER_OK
(( $+commands[$EDITOR] )) && print "ZSH_EDITOR_OK:$EDITOR"
PROBE
zsh_out="$(run_in_pty "zsh -i -c 'source $probe'")"
check "zsh -i" "$zsh_out" ZSH_LS_OK ZSH_LL_OK ZSH_L_OK ZSH_MANPAGER_OK ZSH_EDITOR_OK

echo PASS
