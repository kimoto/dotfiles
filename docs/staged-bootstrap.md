# Bootstrap phases

The config is brought up in phases. Each phase adds to the one before, and no
phase may break because a later phase's tools are missing, so a machine that
can only get so far still works at the phase it reached. CI checks each one on
its own.

| Phase | Assumes | May install | Gate |
|---|---|---|---|
| minimal | nothing can be installed | nothing: the OS's bash, vim and git | `test/e2e/mkworld_phase_test.sh minimal`, `test/e2e/plain_shell_test.sh` (bash half) |
| basic | the OS has zsh | only what a git clone brings; no extra binary | `test/e2e/mkworld_phase_test.sh basic`, `test/e2e/plain_shell_test.sh` (zsh half), `vim_guard_test` |
| standard | tools can be installed | `Brewfile.standard` | `test/e2e/zsh_loading_test.sh` (`zsh_loading_test_standard_only`) |
| extra | your own machine | `Brewfile.extra`, tpm/nvim plugins, mise runtimes | `test/e2e/tmux_loading_test.sh`, `run_tests.sh`, the tmux e2e set, `test/e2e/nvim_loading_test.sh` |
| platform | this OS | `Brewfile.macos` + `setup_macosx.sh`, or `Brewfile.linux` | `bootstrap-macos`, `bootstrap-monthly` |

## Where a tool goes

- **basic | standard: does it need a separate binary?** sheldon is one, so the
  zsh plugins it loads are standard.
- **standard | extra: does installing it change everyday use, with no other
  step?** eza (`ls`), bat (`cat`), zoxide (`cd`), delta (`git diff`), fzf
  (^R) do. kubectl, jq, tmux do not: they run only when typed, even
  when the config carries a completion or a key binding for them.
- **extra | platform: does only one OS get it?** GUI casks, macOS system
  settings and Linux stand-ins go last: they fail most often, and a failure
  there should not cost extra.

Agent containers sit outside the phases, since an agent, not a person, uses
that shell: `bin/setup_agent.sh` installs the check binaries and links the
Claude and Codex configuration, nothing a person types with.

## When a phase cannot be reached

`bin/mkworld.sh` climbs the phases in order and stops at the first one it
cannot reach (no zsh, no sudo for Homebrew, a failed `brew bundle`). Its last
line says `mkworld: reached <phase>` and why; it exits 0 unless even minimal
failed. `brew bundle check` decides standard and extra, so a caller that
installed the bundles itself (`SKIP_BREW=1`) is judged the same way.

A caller that knows how far it should get sets `MKWORLD_EXPECT=<phase>`, and a
lower result exits 1: CI's brew jobs expect standard, the bootstrap jobs
expect platform.

Steps that are not a phase (tpm plugins, the Claude Code hooks, mise, lefthook)
run after the climb whenever their own tool is present, and only warn on
failure.
