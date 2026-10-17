# Staged bootstrap — design note

Status: **planned, not implemented.** Written up so the work can start from a
list instead of from scratch. Nothing in `bin/` implements this yet.

## The problem

`bin/mkworld.sh` is all-or-nothing. It runs under `set -e`, so the first
non-zero exit anywhere aborts every remaining step, and `set -x` buries that
fact in several hundred lines of trace.

This is not hypothetical. `mkworld.sh` died at the Homebrew step on Ubuntu: it
launched a `#!/bin/bash` helper via `sh`, which is dash there and rejects
`set -o pipefail`. Everything after that step — submodules, tpm plugins, the
Claude Code tmux hooks, `lefthook install` — never ran. Nothing said so. The
machine looked bootstrapped and was not.

The goal: **bring the machine up in tiers, and prove each tier works before
installing the next one.** If a later tier stumbles, the earlier ones still hold
and the machine stays operable.

## The phases

Each phase adds to the one before, and no phase may break because a later
phase's tools are missing. CI checks each one on its own.

| Phase | Assumes | May install | Gate |
|---|---|---|---|
| minimal | nothing can be installed | nothing: the OS's bash, vim and git | `ci_plain_shell_test.sh` (bash half) |
| basic | the OS has zsh | only what a git clone brings (vim's NeoBundle plugins); no extra binary | `ci_plain_shell_test.sh` (zsh half), `vim_guard_test` |
| standard | tools can be installed | `Brewfile.standard` | `ci_zsh_loading_test.sh` (`zsh_loading_test_standard_only`) |
| full | your own machine | `Brewfile.full` (tmux included) + platform Brewfile, tpm/nvim plugins, mise runtimes | `ci_tmux_loading_test.sh`, `run_tests.sh`, the tmux e2e set, `ci_nvim_loading_test.sh` |

Two boundaries decide where a tool goes:

- **basic | standard: does it need a separate binary?** sheldon is one, so the
  zsh plugins it loads are standard, while NeoBundle (cloned by `.vimrc`
  itself) stays basic.
- **standard | full: does installing it change everyday use, with no other
  step?** eza (`ls`), bat (`cat`), zoxide (`cd`), delta (`git diff`), fzf
  (^R) do. kubectl, lazygit, jq do not: they run only when typed, even when
  the config carries a completion or a key binding for them.

Cloud sessions sit outside the phases: they link only `~/.claude`
(`bin/link_claude_dir.sh --cloud`), since an agent, not a person, uses that
shell.

## Design decisions

**1. Record and continue, do not `set -e` the whole run.** Today "this stage
failed" and "abort everything" are the same thing. Instead: run each stage,
record pass/fail, keep going wherever the dependency allows, print a summary,
exit non-zero if anything failed. `bin/brew_bundle_install.sh` already works
this way (unattended pass → collect failures → interactive phase at the end),
so there is a precedent in-tree to copy rather than invent.

**2. Gate on the self-test, not on the installer's exit code.** A `brew bundle
install` that exits non-zero because one cask failed does not mean the shell is
broken. The only question that decides whether to continue is "does the shell
still load", and `ci_zsh_loading_test.sh` already answers exactly that.

**3. Reorder while we are in there.** `mkworld.sh` currently runs `lefthook
install` and the Claude tmux hooks *last*, after the slowest and most
network-dependent work. Cheap, local, high-value steps should come first.

Wanted alongside: resumability (`--from=full`, or a stamp file per completed
phase), and an escape hatch printed when standard fails ("you are in bash, here
is how to recover").

## tmux is in full

tmux runs only when typed, so the phase boundary puts it in full. Two findings
say the standard gate does not miss it:

- **`.zshrc` does not need the tmux binary.** Both places it touches tmux
  (`update_tmux_window`, `_tmux_prompt_mark`, both `precmd` hooks) open with
  `[[ -n "$TMUX" ]] || return`. With no tmux, `$TMUX` is unset and they return
  before ever calling it.
- **Only two of the sixteen `bin/ci_*_test.sh` self-tests run without tmux:**
  `ci_zsh_loading_test.sh` (it takes its pty from `script`, not from tmux) and
  `ci_nvim_guard_test.sh`. Every other one drives a real terminal through tmux.

So the standard gate is tmux-free by construction. CI installs tmux on demand
in `bin/ci_prepare.sh` for the tests that drive a terminal through it.

## The first brick, which is worth doing on its own

**Done:** `zsh_loading_test_standard_only` in `.github/workflows/ci.yml`. It
installs only `Brewfile.standard` plus the symlinks (`mklink.sh`), skipping tmux
and the tmux-plugin/Claude-hooks/lefthook work `mkworld.sh` does, and runs
only `ci_zsh_loading_test.sh`.

Before this job existed, nothing verified that the standard phase alone produces
a working shell — the existing `zsh_loading_test` job installs tmux on
top and then runs the whole e2e set, so a break in `Brewfile.standard` alone could
still pass it.
