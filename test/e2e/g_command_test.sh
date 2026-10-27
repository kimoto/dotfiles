#!/bin/bash
# Interactive end-to-end test for the `g` repo-jump command defined in .zshrc.
#
# `g` is the most moving-part-heavy helper in .zshrc: bin/ghq_pick.sh pipes
# ghq list (ranked by zoxide; test/ghq_pick.bats covers the order) into fzf,
# with the `$*` argument prefilled as the query and a bat-of-README preview,
# and `g` cds into `$(ghq root)/<selection>`. Three things can
# only be proven by driving it for real, in a terminal:
#   1. the ghq candidate list is piped into fzf and the function argument
#      pre-filters it (`--query`);
#   2. the preview pane actually renders the highlighted repo's README, which
#      exercises the `$(ghq root)/{}/README.*` path construction; and
#   3. selecting cd's into `$(ghq root)/<dir>`, while aborting leaves $PWD put.
#
# Like test/e2e/tmux_interactive_test.sh this drives a real terminal via tmux
# send-keys + capture-pane (the TUI analogue of a browser e2e). fzf is real;
# the external `ghq` and `bat` are stubbed on PATH so the test is hermetic and
# needs no network, no real checkouts, and no bat install.
#
# shellcheck disable=SC2016  # send-keys strings are single-quoted on purpose:
# every `$PWD`/`$(...)` must be evaluated by the zsh inside the pane, not here.
set -euo pipefail

# Shared e2e plumbing: die/need, the brew shellenv, and zsh_pane_cmd.
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/tmux_e2e_helpers.sh"

need tmux
need zsh
command -v fzf  >/dev/null 2>&1 || die "fzf not installed (g pipes ghq list into fzf)"
ZSH_BIN="$(command -v zsh)"
REPO="$PWD"
[ -f "$REPO/.zshrc" ] || die "no .zshrc in $REPO"
echo "== $(tmux -V), $("$ZSH_BIN" --version), $(fzf --version) =="

# ---------------------------------------------------------------------------
# Hermetic fixture: a fake ghq world + stubbed ghq/bat on PATH.
# ---------------------------------------------------------------------------
TMP="$(mktemp -d)"
GHQ_ROOT="$TMP/ghq"
STUB_BIN="$TMP/bin"
mkdir -p "$STUB_BIN"

# Three repos. Each README carries a unique marker so the preview assertion can
# tell exactly which repo fzf highlighted.
declare -A REPOS=(
  [github.com/alice/alpha]=READMEMARK_ALPHA
  [github.com/bob/beta]=READMEMARK_BETA
  [github.com/carol/gamma]=READMEMARK_GAMMA
)
for path in "${!REPOS[@]}"; do
  mkdir -p "$GHQ_ROOT/$path"
  printf '# %s\n\n%s\n' "$path" "${REPOS[$path]}" >"$GHQ_ROOT/$path/README.md"
done

# Stub ghq: `list` prints repo-relative paths (sorted, stable order for the
# pane assertions), `root` prints the fake root. Anything else is a no-op.
cat >"$STUB_BIN/ghq" <<EOF
#!/bin/sh
case "\$1" in
  list) printf '%s\n' 'github.com/alice/alpha' 'github.com/bob/beta' 'github.com/carol/gamma' ;;
  root) printf '%s\n' '$GHQ_ROOT' ;;
  *) : ;;
esac
EOF

# Stub bat: ignore every -flag and cat the first file argument. fzf's preview
# shell expands the `README.*` glob, so bat receives the concrete README path.
cat >"$STUB_BIN/bat" <<'EOF'
#!/bin/sh
for a in "$@"; do
  case "$a" in -*) ;; *) f="$a"; break ;; esac
done
[ -n "${f:-}" ] && cat "$f"
EOF

chmod +x "$STUB_BIN/ghq" "$STUB_BIN/bat"

SOCK="ci_g_e2e_$$"
cleanup() { tmux -L "$SOCK" kill-server 2>/dev/null || true; rm -rf "$TMP" 2>/dev/null || true; }
trap cleanup EXIT

# Launch an interactive zsh in a real terminal, under the shared CI pane
# conventions (see zsh_pane_cmd in tmux_e2e_helpers.sh). The stub bin goes into
# the pane's environment so anything .zshrc spawns inherits it too.
tmux -L "$SOCK" new-session -d -x 200 -y 50 "$(zsh_pane_cmd "PATH=$STUB_BIN:$PATH")" ||
  die "failed to start tmux session"

# ...and re-prepend it once the shell is up, because .zshrc rebuilds $path with
# the Homebrew bin directories *ahead* of whatever it inherited. On a machine
# that has the real ghq installed (any full workstation — ghq is in
# Brewfile.extra) that real ghq shadows the stub and the fixture silently
# stops being hermetic: `ghq root` answers with the developer's own ~/ghq.
# CI never noticed because it installs Brewfile.standard only, so there is no real
# ghq there to win.
tmux -L "$SOCK" send-keys "export PATH=$STUB_BIN:\$PATH" Enter

# 0) Shell is live and our fixtures are the ones on PATH (proves the env took).
tmux -L "$SOCK" send-keys 'echo __G_READY__$((6 * 7)):$(ghq root)' Enter
wait_for_pane "$SOCK" "__G_READY__42:$GHQ_ROOT"
echo "== shell live; stub ghq on PATH =="

# `cd` is aliased to `z` (zoxide) in interactive shells (.zshrc line: `alias
# cd=z`), and `z` is defined by `zoxide init zsh` via sheldon. In CI the real
# zoxide is present (Brewfile.standard) and used as-is. For a minimal local run
# without the sheldon plugin bootstrap, define a cd-equivalent `z` fallback so
# g's `cd "$(ghq root)/$dir"` still changes directory.
tmux -L "$SOCK" send-keys 'command -v z >/dev/null 2>&1 || z() { builtin cd "$@"; }' Enter

# 1) `g <query>` pipes ghq list into fzf, the argument pre-filters to a single
#    repo, and the preview pane renders THAT repo's README (the bat-of-README
#    path construction). The query "alpha" matches only github.com/alice/alpha,
#    so the alpha marker — and only it — must appear in the preview.
tmux -L "$SOCK" send-keys 'g alpha' Enter
wait_for_pane "$SOCK" 'github.com/alice/alpha'
wait_for_pane "$SOCK" 'READMEMARK_ALPHA'
echo "== fzf opened, query filtered to alpha, README preview rendered =="

# 2) Selecting (Enter) cd's into `$(ghq root)/<dir>`. Marker carries $PWD so the
#    assertion is unambiguous about which directory we landed in.
tmux -L "$SOCK" send-keys Enter
tmux -L "$SOCK" send-keys 'echo __G_CD__:$PWD' Enter
wait_for_pane "$SOCK" "__G_CD__:$GHQ_ROOT/github.com/alice/alpha"
echo "== Enter cd'd into the selected repo =="

# 3) Aborting an `g` (no match -> fzf's --exit-0 returns nothing) must NOT cd:
#    $PWD stays at the alpha repo from step 2. A distinct marker avoids matching
#    the earlier line in scrollback.
tmux -L "$SOCK" send-keys 'g zzz_no_such_repo' Enter
tmux -L "$SOCK" send-keys 'echo __G_NOCD__:$PWD' Enter
wait_for_pane "$SOCK" "__G_NOCD__:$GHQ_ROOT/github.com/alice/alpha"
echo "== no-match abort left \$PWD unchanged (no cd) =="

# 4) Bare `g` (empty query) shows the full candidate list. Assert a different
#    repo than alpha is present, then abort with Esc and confirm no cd happened.
tmux -L "$SOCK" send-keys 'g' Enter
wait_for_pane "$SOCK" 'github.com/carol/gamma'
tmux -L "$SOCK" send-keys Escape
wait_absent_pane "$SOCK" 'github.com/carol/gamma'   # fzf fully closed before typing again
tmux -L "$SOCK" send-keys 'echo __G_ESC__:$PWD' Enter
wait_for_pane "$SOCK" "__G_ESC__:$GHQ_ROOT/github.com/alice/alpha"
echo "== bare g listed all repos; Esc aborted without cd =="

echo "PASS"
