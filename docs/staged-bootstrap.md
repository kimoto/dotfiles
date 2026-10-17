# Bootstrap phases

The config is brought up in phases. Each phase adds to the one before, and no
phase may break because a later phase's tools are missing, so a machine that
can only get so far still works at the phase it reached. CI checks each one on
its own.

| Phase | Assumes | May install | Gate |
|---|---|---|---|
| minimal | nothing can be installed | nothing: the OS's bash, vim and git | `ci_mkworld_phase_test.sh minimal`, `ci_plain_shell_test.sh` (bash half) |
| basic | the OS has zsh | only what a git clone brings (vim's NeoBundle plugins); no extra binary | `ci_mkworld_phase_test.sh basic`, `ci_plain_shell_test.sh` (zsh half), `vim_guard_test` |
| standard | tools can be installed | `Brewfile.standard` (plus the platform Brewfile) | `ci_zsh_loading_test.sh` (`zsh_loading_test_standard_only`) |
| full | your own machine | `Brewfile.full`, tpm/nvim plugins, mise runtimes | `ci_tmux_loading_test.sh`, `run_tests.sh`, the tmux e2e set, `ci_nvim_loading_test.sh` |

## Where a tool goes

- **basic | standard: does it need a separate binary?** sheldon is one, so the
  zsh plugins it loads are standard, while NeoBundle (cloned by `.vimrc`
  itself) stays basic.
- **standard | full: does installing it change everyday use, with no other
  step?** eza (`ls`), bat (`cat`), zoxide (`cd`), delta (`git diff`), fzf
  (^R) do. kubectl, lazygit, jq, tmux do not: they run only when typed, even
  when the config carries a completion or a key binding for them.

Cloud sessions sit outside the phases: they link only `~/.claude`
(`bin/link_claude_dir.sh --cloud`), since an agent, not a person, uses that
shell.

## When a phase cannot be reached

`bin/mkworld.sh` climbs the phases in order and stops at the first one it
cannot reach (no zsh, no sudo for Homebrew, a failed `brew bundle`). Its last
line says `mkworld: reached <phase>` and why; it exits 0 unless even minimal
failed. `brew bundle check` decides standard and full, so a caller that
installed the bundles itself (`SKIP_BREW=1`) is judged the same way.

A caller that knows how far it should get sets `MKWORLD_EXPECT=<phase>`, and a
lower result exits 1: CI's brew jobs expect standard, the monthly bootstrap
expects full.

Steps that are not a phase (tpm plugins, the Claude Code hooks, mise, lefthook)
run after the climb whenever their own tool is present, and only warn on
failure.
