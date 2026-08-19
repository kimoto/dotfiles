#!/usr/bin/env bats

# The tmux prefix hint is written out twice: once as `@prefix_hint` in
# .tmux.conf (what tmux actually draws while the prefix is held) and once as
# prose in KEYBINDINGS.md telling the reader what to expect there.
#
# Nothing else pins those two together. bin/ci_tmux_status_test.sh renders the
# configured hint and asserts every key pair, so the config and that test cannot
# drift apart unnoticed — but the document can, and a keybinding reference that
# misquotes what is on screen is worse than one that says nothing. This is that
# missing pin; adding a key to the hint now fails here until the doc follows.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CONF="$REPO_ROOT/.tmux.conf"
  DOC="$REPO_ROOT/KEYBINDINGS.md"
}

# The hint as tmux stores it: continuation lines folded in (a trailing `\` joins
# the next line), the quoted value taken, then the #[...] style runs dropped —
# they are what colors the keys, and are invisible on screen.
conf_hint() {
  sed -e :a -e '/\\$/{N;s/\\\n//;ta}' "$CONF" |
    sed -n 's/^set -g @prefix_hint "\(.*\)"$/\1/p' |
    sed -e 's/#\[[^]]*\]//g' -e 's/^ *//' -e 's/ *$//'
}

# The first backticked span of the "While the prefix is held" paragraph in the
# tmux section (the paragraph also mentions `prefix + b`, hence first only).
doc_hint() {
  awk '/^While the prefix is held/ { found = 1 }
       found && /^$/ { exit }
       found { printf "%s ", $0 }' "$DOC" |
    grep -o '`[^`]*`' | head -n 1 | tr -d '`'
}

@test "the hint is both configured and documented" {
  [ -n "$(conf_hint)" ]
  [ -n "$(doc_hint)" ]
}

@test "KEYBINDINGS.md quotes the prefix hint exactly as tmux renders it" {
  local doc conf
  doc="$(doc_hint)"
  conf="$(conf_hint)"
  if [ "$doc" != "$conf" ]; then
    echo "KEYBINDINGS.md says: [$doc]" >&2
    echo ".tmux.conf renders : [$conf]" >&2
    return 1
  fi
}
