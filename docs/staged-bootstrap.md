# Staged bootstrap — design note

Status: **the climb is implemented** in `bin/mkworld.sh`; resumability and the
recovery hint below are not.

## The problem

`bin/mkworld.sh` was all-or-nothing. It ran under `set -e`, so the first
non-zero exit anywhere aborted every remaining step, and `set -x` buried that
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
| minimal | nothing can be installed | nothing: the OS's bash, vim and git | `ci_mkworld_phase_test.sh minimal`, `ci_plain_shell_test.sh` (bash half) |
| basic | the OS has zsh | only what a git clone brings (vim's NeoBundle plugins); no extra binary | `ci_mkworld_phase_test.sh basic`, `ci_plain_shell_test.sh` (zsh half), `vim_guard_test` |
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

**1. Climb, and stop one phase down instead of aborting.** `mkworld.sh` tries
the phases in order. The first one it cannot reach ends the climb, and the
machine is left at the phase below, which works on its own. The last line says
`mkworld: reached <phase>` and why it stopped; the exit status is 0 unless even
minimal failed. A caller that knows how far it should get sets
`MKWORLD_EXPECT=<phase>`, and a lower result exits 1: CI's brew jobs expect
standard, the monthly bootstrap expects full.

Steps that are not a phase (tpm plugins, the Claude Code hooks, mise, lefthook)
run after the climb whenever their own tool is present, and only warn on
failure.

**2. A phase is reached when its Brewfile is satisfied, and CI proves its shell
works.** `brew bundle check` decides standard and full, so a caller that
installed the bundle itself (`SKIP_BREW=1`) is judged the same way. Whether the
shell still loads at that phase is the self-tests' job, per the table above.

**3. Climb in phase order.** The NeoBundle submodule is basic, so it runs before
Homebrew; it used to run after, and a failed Homebrew install left even basic
unfinished.

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
