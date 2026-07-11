#!/bin/bash

set -euo pipefail

export TERM="xterm-256color"
export COLORTERM="truecolor"
# Don't run the dotfiles sync reminder during the load test: it would touch the
# network (background fetch) and print reminder noise unrelated to this check.
export DOTFILES_NO_SYNC_CHECK=1
# Likewise skip the Brewfile drift reminder: CI installs only Brewfile.basic, so
# a check would always report common/* missing, and `brew bundle check` is slow.
export DOTFILES_NO_BREW_CHECK=1

die() {
  echo "CI error: $*" >&2
  exit 1
}

run_zsh() {
  local cmd="source \"$ZDOTDIR/.zshrc\"; $*"
  if command -v script >/dev/null 2>&1; then
    # Allocate a pseudo-tty so zle widgets can initialize in CI.
    # Try Linux util-linux syntax (options before file).
    if script -q -c "true" /dev/null </dev/null >/dev/null 2>&1; then
      script -q -c "env CI= $ZSH_BIN -ic \"$cmd\"" /dev/null 2>&1
      return
    fi
    # Try older Linux / macOS syntax.
    if script -q /dev/null -c "true" </dev/null >/dev/null 2>&1; then
      script -q /dev/null -c "env CI= $ZSH_BIN -ic \"$cmd\"" 2>&1
      return
    fi
  fi
  # Fallback: no pseudo-tty (zle warnings are harmless).
  env CI= "$ZSH_BIN" -ic "$cmd" 2>&1
}

require_grep() {
  local label="$1"
  local haystack="$2"
  local pattern="$3"

  if ! printf '%s\n' "$haystack" | grep -q "$pattern"; then
    die "$label"
  fi
}

if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  ZSH_BIN="/home/linuxbrew/.linuxbrew/bin/zsh"
else
  ZSH_BIN="${ZSH_BIN:-zsh}"
fi

log_file="$(mktemp)"
export ZDOTDIR="$PWD"
if ! env CI= "$ZSH_BIN" "$ZDOTDIR/.zshrc" >"$log_file" 2>&1; then
  cat "$log_file"
  exit 1
fi
if grep -E "command not found|evalcache: ERROR" "$log_file"; then
  cat "$log_file"
  exit 1
fi
cat "$log_file"

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
echo "== starship prompt =="
prompt_out="$(STARSHIP_SHELL=zsh STARSHIP_CONFIG="$XDG_CONFIG_HOME/starship.toml" PWD="$PWD" starship prompt)"
echo "== starship prompt (initial) =="
printf '%s\n' "$prompt_out"
tmp_dir="$(mktemp -d)"
tmp_base="$(basename "$tmp_dir")"
moved_out="$(STARSHIP_SHELL=zsh STARSHIP_CONFIG="$XDG_CONFIG_HOME/starship.toml" PWD="$tmp_dir" starship prompt)"
echo "== starship prompt after cd =="
printf '%s\n' "$moved_out"
if [ "$prompt_out" = "$moved_out" ]; then
  die "prompt did not change after directory update"
fi
if ! printf '%s\n' "$moved_out" | grep -F "$tmp_base" >/dev/null; then
  die "prompt did not reflect directory change ($tmp_base)"
fi

echo "== ls function =="
# ls is a function, not a plain alias (see .zshrc: --hyperlink is TTY-gated),
# so check its body instead of `alias ls`.
ls_fn_out="$(run_zsh 'whence -f ls')"
printf '%s\n' "$ls_fn_out"
require_grep "ls function does not use eza" "$ls_fn_out" "eza"

echo "== ls -l bin/mkworld.sh =="
ls_out="$(run_zsh 'ls -l bin/mkworld.sh')"
printf '%s\n' "$ls_out"
require_grep "ls -l output missing bin/mkworld.sh" "$ls_out" "mkworld.sh"

# Extended assertions: confirm the rest of .zshrc's aliases, env vars, options,
# functions and keybindings actually take effect after an interactive load.
#
# The probe is written to a temp file and sourced, rather than passed inline to
# run_zsh. run_zsh runs the command through nested shells (script -c "... zsh
# -ic \"$cmd\""), so any `$VAR` written inline would be expanded by the
# intermediate shell (where it is empty) before the inner zsh ever sees it.
# Sourcing a file keeps every `$` expansion inside the inner zsh, after .zshrc
# has loaded. It still loads .zshrc only once.
echo "== extended .zshrc assertions =="
probe="$(mktemp)"
cat >"$probe" <<'PROBE'
alias ll
alias vi
alias cat
alias reload
print "EDITOR=$EDITOR"
print "VISUAL=$VISUAL"
print "PAGER=$PAGER"
print "HOMEBREW_PREFIX=${HOMEBREW_PREFIX:-unset}"
print "ZCOMPDUMP_ZWC=$([[ -s ${ZDOTDIR:-$HOME}/.zcompdump.zwc ]] && echo yes || echo no)"
for o in autocd autopushd share_history interactivecomments noclobber; do
  [[ -o $o ]] && print "OPT_ON:$o"
done
for fn in temp lg g l px livegrep snip keys source-if-exist; do
  whence -w "$fn"
done
bindkey "^G"
bindkey "^X^N"
PROBE
env_out="$(run_zsh "source '$probe'")"
rm -f "$probe"
printf '%s\n' "$env_out"

# aliases
require_grep "ll alias missing --long flags"   "$env_out" "ll=.*--long"
require_grep "vi is not aliased to nvim"        "$env_out" "vi=.*nvim"
require_grep "cat is not aliased to bat"        "$env_out" "cat=.*bat"
require_grep "reload is not aliased to exec zsh" "$env_out" "reload=.*exec zsh"

# environment variables
require_grep "EDITOR is not nvim"   "$env_out" "EDITOR=nvim"
require_grep "VISUAL is not nvim"   "$env_out" "VISUAL=nvim"
require_grep "PAGER does not use less" "$env_out" "PAGER=less"

# brew shellenv: exported via the _evalcache inline in sheldon's plugins.toml,
# not a direct eval in .zshrc. Gated on brew so brew-less boxes still pass.
if command -v brew >/dev/null 2>&1; then
  require_grep "HOMEBREW_PREFIX not exported (brew-shellenv evalcache inline)" "$env_out" "HOMEBREW_PREFIX=/"
fi

# compinit dump is compiled to wordcode so later startups parse it faster.
require_grep ".zcompdump.zwc missing (zcompile after compinit)" "$env_out" "ZCOMPDUMP_ZWC=yes"

# shell options (setopt)
for opt in autocd autopushd share_history interactivecomments noclobber; do
  require_grep "setopt not enabled: $opt" "$env_out" "OPT_ON:$opt"
done

# utility functions defined in .zshrc
for fn in temp lg g l px livegrep snip keys source-if-exist; do
  require_grep "function not defined: $fn" "$env_out" "$fn: function"
done

# zle widgets / keybindings
require_grep "livegrep not bound to ^G" "$env_out" "livegrep"
require_grep "snippet widget not bound to ^X^N" "$env_out" "search_snippet_and_replace_lbuffer"

# carapace completion: carapace ships in Brewfile.basic, so it's present in CI.
# Confirms the eval-cache inline actually registers a completer for `carapace`,
# checked via zsh's _comps map (command -> completion function) so the assertion
# doesn't depend on carapace's internal function name. Gated on presence so the
# test still runs on machines without carapace installed.
if command -v carapace >/dev/null 2>&1; then
  echo "== carapace completion =="
  carapace_probe="$(mktemp)"
  cat >"$carapace_probe" <<'PROBE'
print "CARAPACE_COMP=${_comps[carapace]:-none}"
PROBE
  carapace_out="$(run_zsh "source '$carapace_probe'")"
  rm -f "$carapace_probe"
  printf '%s\n' "$carapace_out"
  require_grep "carapace completion not registered (installed path)" "$carapace_out" "CARAPACE_COMP=_"
fi

# Startup time gate: prevent regressions from the startup-perf pass.
# Measures a bare interactive-exit (loads .zshrc then quits) using GNU date
# +%s%N, which is available on ubuntu-latest.  5s is generous enough to absorb
# Linuxbrew/CI overhead while still catching a serious regression — re-enabling
# hook-env or loading a heavy plugin synchronously typically adds 30-200ms on a
# developer machine and compounds to 500ms+ on CI.
echo "== zsh startup time budget =="
_t0=$(date +%s%N)
env CI= "$ZSH_BIN" -ic exit >/dev/null 2>&1 || true
_t1=$(date +%s%N)
startup_ms=$(( (_t1 - _t0) / 1000000 ))
printf 'Startup time: %dms (budget: 5000ms)\n' "$startup_ms"
if [ "$startup_ms" -gt 5000 ]; then
  die "zsh startup too slow: ${startup_ms}ms exceeds 5000ms budget"
fi
