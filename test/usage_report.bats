#!/usr/bin/env bats

# usage_report.sh reads the last-used date of each alias and function out of
# the zsh history. What matters is that a name typed recently stays off the
# list, one typed long ago or never is on it, and names nobody types (hooks,
# widgets, startup helpers) never show up as "never used".

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK="$(mktemp -d)"
  export HISTFILE="$WORK/history"
  export USAGE_REPORT_CONFIG="$WORK/zshrc"
  export USAGE_REPORT_NOW=1760600000 # 2025-10-16
  cat >"$USAGE_REPORT_CONFIG" <<'EOF'
alias recent='echo'
alias stale='echo'
  alias indented='echo'
unused() { :; }
function piped { :; }
_private() { :; }
widget() { :; }
zle -N widget
hooked() { :; }
add-zsh-hook precmd hooked
chpwd() { :; }
helper() { :; }
helper "$HOME/.zshrc.local"
# commented() { :; }
EOF
}

teardown() {
  rm -rf "$WORK"
}

report() {
  run "$REPO_ROOT/bin/usage_report.sh" "$@"
}

@test "lists names unused for 90 days, oldest first, and leaves out recent ones" {
  cat >"$HISTFILE" <<'EOF'
: 1760500000:0;recent
: 1700000000:0;stale arg
EOF
  report
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "# history since 2023-11-14" ]
  [ "${lines[1]}" = "$(printf '2023-11-14\talias\tstale')" ]
  [[ "$output" != *recent* ]]
  [[ "$output" == *"$(printf 'never\talias\tindented')"* ]]
  [[ "$output" == *"$(printf 'never\tfunction\tunused')"* ]]
}

@test "counts a name used after a pipe, under sudo, or on a continuation line" {
  cat >"$HISTFILE" <<'EOF'
: 1760500000:0;ls | piped
: 1760500000:0;sudo indented
: 1760500000:0;for i in 1 2; do \
unused; done
EOF
  report
  [ "$status" -eq 0 ]
  [[ "$output" != *piped* ]]
  [[ "$output" != *indented* ]]
  [[ "$output" != *unused* ]]
}

@test "never lists hooks, widgets, startup helpers, private or commented names" {
  : >"$HISTFILE"
  printf ': 1760500000:0;ls\n' >"$HISTFILE"
  report --all
  [ "$status" -eq 0 ]
  for name in _private widget hooked chpwd helper commented; do
    [[ "$output" != *"$name"* ]]
  done
}

@test "--all also shows recently used names" {
  printf ': 1760500000:0;recent\n' >"$HISTFILE"
  report --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(printf '2025-10-15\talias\trecent')"* ]]
}

@test "fails instead of calling everything unused when the history has no stamps" {
  printf 'recent\nstale\n' >"$HISTFILE"
  report
  [ "$status" -eq 1 ]
  [[ "$output" == *extended_history* ]]
}

@test "the real .zshrc yields names, none of them hooks or widgets" {
  unset USAGE_REPORT_CONFIG
  printf ': 1760500000:0;ls\n' >"$HISTFILE"
  report --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(printf 'never\talias\treload')"* ]]
  for name in chpwd update_tmux_window keys_widget pasteinit source-if-exist _abbr_expand; do
    [[ "$output" != *"$name"* ]]
  done
}
