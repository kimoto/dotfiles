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

## The stages

The layering and the self-tests both already exist — what is missing is the
wiring between them.

| Stage | Installs | Gate (existing script) |
|---|---|---|
| 0 | `mklink.sh` — symlinks only, no network | symlinks resolve |
| 1 | `Brewfile.basic` | `ci_zsh_loading_test.sh` |
| 2 | `Brewfile.common` + platform Brewfile | `ci_tmux_loading_test.sh`, `run_tests.sh`, the tmux e2e set |
| 3 | tpm plugins, nvim plugins, mise runtimes, NeoBundle | `ci_nvim_loading_test.sh`, `ci_vim_loading_test.sh` |

Stage 1 green means "the shell works" — the whole point. Stage 3 holds the
flakiest work (third-party clones, network) and the least essential.

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

Wanted alongside: resumability (`--from=2`, or a stamp file per completed
stage), and an escape hatch printed when stage 1 fails ("you are in bash, here
is how to recover").

## tmux belongs in stage 2, not stage 1

Today `brew "tmux"` sits in `Brewfile.basic`. The justification is circular: the
split rule says a package is `basic` if removing it breaks
`ci_zsh_loading_test.sh` *or* `ci_tmux_loading_test.sh` — and the only thing the
second test needs tmux for is tmux itself. That is a different kind of reason
from starship's, which `.zshrc` genuinely calls while loading.

Two findings say the boundary is right where tmux sits:

- **`.zshrc` does not need the tmux binary.** Both places it touches tmux
  (`update_tmux_window`, `_tmux_prompt_mark`, both `precmd` hooks) open with
  `[[ -n "$TMUX" ]] || return`. With no tmux, `$TMUX` is unset and they return
  before ever calling it.
- **Only two of the sixteen `bin/ci_*_test.sh` self-tests run without tmux:**
  `ci_zsh_loading_test.sh` (it takes its pty from `script`, not from tmux) and
  `ci_nvim_guard_test.sh`. Every other one drives a real terminal through tmux.

So the stage-1 gate is tmux-free by construction — it does not depend on what
stage 2 installs — and everything that does need tmux already lives on the
other side of the line.

### What moving `brew "tmux"` to `Brewfile.common` touches

- `Brewfile.basic` header — drop the `ci_tmux_loading_test.sh` clause from the
  litmus test; `basic` becomes "what `.zshrc` calls at load time".
- `AGENTS.md` — restates the same split rule, same edit.
- `bin/ci_prepare.sh` — must install tmux on demand. There is an exact precedent
  three lines above: fzf is already handled this way ("not in Brewfile.basic, so
  install on demand"). The comment there claiming "tmux already came in via
  Brewfile.basic" becomes wrong.
- `.github/workflows/ci.yml` — the Homebrew cache key is
  `...-${{ hashFiles('Brewfile.basic') }}-fzf-v3`, and its comment says "tmux IS
  in Brewfile.basic, so the hash already covers it". Both stop being true: bump
  the suffix (`-fzf-tmux-v4`) so the cache is rebuilt with tmux baked in.

### Sequencing

Doing this move *before* the stages exist buys nothing operationally —
`mkworld.sh` installs basic + common + platform in one shot either way — while
still churning the CI cache. It belongs with the staging work, not ahead of it.

## The first brick, which is worth doing on its own

A CI job that installs **only `Brewfile.basic`** (no fzf, no tmux) and runs
**only `ci_zsh_loading_test.sh`**.

Nothing verifies today that the minimal tier alone produces a working shell —
the existing `zsh_loading_test` job installs fzf and tmux on top and then runs
the whole e2e set. The new job is fast (no plugin clones, no fzf) and is
effectively the stage-1 gate in prototype form, so it can land before any of the
above and keep paying off regardless.
