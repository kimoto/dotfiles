#!/bin/bash

set -euo pipefail

export TERM="xterm-256color"
export COLORTERM="truecolor"

die() {
  echo "CI error: $*" >&2
  exit 1
}

run_zsh() {
  local cmd="source \"$ZDOTDIR/.zshrc\"; $*"
  if command -v script >/dev/null 2>&1; then
    # Allocate a pseudo-tty so zle widgets can initialize in CI.
    if script -q /dev/null -c "true" </dev/null >/dev/null 2>&1; then
      script -q /dev/null -c "env CI= $ZSH_BIN -ic \"$cmd\"" 2>&1
    else
      script -q /dev/null env CI= "$ZSH_BIN" -ic "$cmd" 2>&1
    fi
    return
  fi
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

echo "== alias ls =="
alias_out="$(run_zsh 'alias ls')"
printf '%s\n' "$alias_out"
require_grep "ls is not aliased to eza" "$alias_out" "ls=.*eza"

echo "== ls -l bin/mkworld.sh =="
ls_out="$(run_zsh 'ls -l bin/mkworld.sh')"
printf '%s\n' "$ls_out"
require_grep "ls -l output missing bin/mkworld.sh" "$ls_out" "mkworld.sh"
