#!/bin/bash
# End-to-end test for the *legacy* Vim config (.vimrc) — the NeoBundle-based
# setup, distinct from the Neovim config under config/nvim.
#
# Why this exists: .vimrc bootstraps ~20 plugins through NeoBundle (a deprecated
# plugin manager) plus a compiled vimproc and the solarized colorscheme. On a
# machine where those aren't installed, every `NeoBundle ...` line throws E492,
# `neobundle#begin`/`#end` throw E117, `colorscheme solarized` throws E185, and
# Vim blocks on a "Press ENTER" prompt at every startup. This test installs the
# plugins from scratch and asserts Vim then starts completely clean.
#
# It deliberately does a NO-CACHE, full install on every run: that doubles as a
# link-rot canary for the deprecated upstreams (if one of the old GitHub repos
# disappears, the clone — and this test — fails loudly). Because that is slow
# and network-bound, it is meant to run on a schedule (monthly), not per-push.
#
# Network note: in a restricted sandbox where github.com is only reachable for
# the in-scope repo via a git relay, run with GIT_CONFIG_GLOBAL=/dev/null so the
# plugin clones use plain HTTPS. On GitHub Actions (open network) it's a no-op.
set -euo pipefail

die() { echo "CI error: $*" >&2; exit 1; }

command -v vim  >/dev/null 2>&1 || die "vim not installed"
command -v git  >/dev/null 2>&1 || die "git not installed"
command -v tmux >/dev/null 2>&1 || die "tmux not installed"
REPO="$PWD"
VIMRC="$REPO/.vimrc"
[ -f "$VIMRC" ] || die "no .vimrc in $REPO"
echo "== $(vim --version | head -1) =="

# Isolated HOME so the real ~/.vim is never touched and the run is reproducible.
HOME_DIR="$(mktemp -d)"
SOCK="ci_vim_e2e_$$"
cleanup() {
  tmux -L "$SOCK" kill-server 2>/dev/null || true
  rm -rf "$HOME_DIR" 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$HOME_DIR/.vim/bundle" "$HOME_DIR/.vim/undo" "$HOME_DIR/tmp"
cp "$VIMRC" "$HOME_DIR/.vimrc"
[ -d "$REPO/.vim/template" ] && cp -r "$REPO/.vim/template" "$HOME_DIR/.vim/template"

# ---------------------------------------------------------------------------
# Install: neobundle itself, then every plugin declared in .vimrc.
# ---------------------------------------------------------------------------
# NeoBundle's own headless installer (`vim -c NeoBundleInstall!`) is unreliable,
# so we reproduce its end state directly: clone each `owner/repo` into
# ~/.vim/bundle/<repo-tail>, exactly where NeoBundle would put it. The plugin
# list is parsed from .vimrc so the test never drifts from the real config.
echo "== cloning NeoBundle =="
git clone --depth 1 https://github.com/Shougo/neobundle.vim \
  "$HOME_DIR/.vim/bundle/neobundle.vim" >/dev/null 2>&1 ||
  die "failed to clone neobundle.vim"

# Every `NeoBundle`/`NeoBundleFetch`/`NeoBundleLazy 'owner/repo'` line -> owner/repo.
mapfile -t repos < <(
  grep -oE "^[[:space:]]*NeoBundle(Fetch|Lazy)?[[:space:]]+['\"][^'\"]+['\"]" "$VIMRC" |
    sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/" |
    grep -v '^Shougo/neobundle.vim$' |
    sort -u
)
[ "${#repos[@]}" -gt 0 ] || die "parsed zero plugins from .vimrc (parser broke?)"
echo "== installing ${#repos[@]} plugins from .vimrc =="

fails=()
for repo in "${repos[@]}"; do
  name="${repo##*/}"
  dest="$HOME_DIR/.vim/bundle/$name"
  if git clone --depth 1 "https://github.com/$repo" "$dest" >/dev/null 2>&1; then
    echo "  ok   $repo"
  else
    echo "  FAIL $repo"
    fails+=("$repo")
  fi
done
[ "${#fails[@]}" -eq 0 ] || die "plugin clone failed (link rot?): ${fails[*]}"

# vimproc ships C that NeoBundle compiles via a build hook; do the same so the
# vimproc-backed features don't warn at runtime.
if [ -f "$HOME_DIR/.vim/bundle/vimproc/make_unix.mak" ]; then
  echo "== building vimproc =="
  ( cd "$HOME_DIR/.vim/bundle/vimproc" && make -f make_unix.mak >/dev/null 2>&1 ) &&
    echo "  vimproc.so: $(find "$HOME_DIR/.vim/bundle/vimproc" -name '*.so' -printf '%f\n')" ||
    echo "  warning: vimproc build failed (continuing; startup check is authoritative)"
fi

# ---------------------------------------------------------------------------
# Assert 1 (headless): sourcing .vimrc produces no error messages, the
# colorscheme applied, and representative plugins loaded.
# ---------------------------------------------------------------------------
echo "== headless startup check =="
msgs="$HOME_DIR/messages.txt"
HOME="$HOME_DIR" vim -N -u "$HOME_DIR/.vimrc" \
  -c 'set nomore' \
  -c "redir! > $msgs" \
  -c 'silent messages' \
  -c 'silent echo "COLORSCHEME=".(exists("g:colors_name")?g:colors_name:"none")' \
  -c 'silent echo "UNITE=".(exists(":Unite")?"loaded":"missing")' \
  -c 'silent echo "NEOCOMPL=".(exists(":NeoComplCacheEnable")?"loaded":"missing")' \
  -c 'redir END' -c 'qall!' </dev/null >/dev/null 2>&1 || die "vim exited non-zero on startup"

echo "---- :messages ----"; cat "$msgs"; echo "-------------------"
if grep -nE "E[0-9]{2,}:|Not an editor command|Unknown function|Cannot find color scheme|Error detected" "$msgs"; then
  die "startup produced Vim errors (see :messages above)"
fi
grep -q "COLORSCHEME=solarized" "$msgs" || die "solarized colorscheme not applied"
grep -q "UNITE=loaded"          "$msgs" || die "unite.vim did not load"
grep -q "NEOCOMPL=loaded"       "$msgs" || die "neocomplcache did not load"
echo "== headless startup clean (no errors, plugins + colorscheme loaded) =="

# ---------------------------------------------------------------------------
# Assert 2 (real terminal): the original symptom was a blocking "Press ENTER"
# prompt and an error wall instead of the buffer. Drive Vim in a real tmux
# terminal and confirm it lands on a normal editing screen with neither.
# ---------------------------------------------------------------------------
echo "== real-terminal startup check =="
tmux -L "$SOCK" new-session -d -x 120 -y 40 \
  "env HOME='$HOME_DIR' TERM=xterm-256color vim -N -u '$HOME_DIR/.vimrc'" ||
  die "failed to start tmux session"

screen=""
for _ in $(seq 1 50); do
  screen="$(tmux -L "$SOCK" capture-pane -p 2>/dev/null || true)"
  # The ruler set by .vimrc's statusline shows once the buffer is up.
  printf '%s\n' "$screen" | grep -qE '\[No Name\]|0,0-1|VIM - Vi IMproved' && break
  sleep 0.1
done
if printf '%s\n' "$screen" | grep -qiE 'Press ENTER|Not an editor command|E[0-9]{2,}:|Unknown function'; then
  echo "---- pane ----"; printf '%s\n' "$screen" >&2
  die "Vim showed an error / Press-ENTER prompt on real-terminal startup"
fi
printf '%s\n' "$screen" | grep -qE '\[No Name\]|VIM - Vi IMproved' ||
  { echo "---- pane ----"; printf '%s\n' "$screen" >&2; die "Vim did not reach a normal startup screen"; }
tmux -L "$SOCK" send-keys ':qa!' Enter
echo "== real-terminal startup clean (normal screen, no Press-ENTER) =="

echo "PASS"
