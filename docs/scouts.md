# Scouts

The `## Scouts` section of `AGENTS.md` is what the sweep skills
(`claudecode/skills/refactor-sweep`, `prune-sweep`, `mutation-sweep`),
`speed-watch` and `security-audit` read for this repo. Those skills stop when the section is missing, so it stays even when
nothing below changes. This note holds the why of each line there, and the
calls already made, so a sweep does not propose them again.

## Checks

`./bin/run_tests.sh` is the bats suite CI runs. `lefthook run pre-commit
--all-files` runs every lint CI runs, through the same `bin/` scripts. A
container that has not run `mise install` lacks `typos` and the schema
checker; that red is the environment's, so note it on the default branch and
compare.

## Proof that nothing changed

`bin/behavior_snapshot.sh compare origin/main` prints every option, alias, key,
function and variable that `.zshrc`, `.tmux.conf`, `.vimrc` and `.bashrc` leave
behind, on both sides, and fails on any difference. It loads no plugins, so
`config/sheldon/plugins.toml` and the `config/zsh/*.zsh` files only it sources
are outside it: a refactor there needs a test that runs the changed lines.
A comment-only change can be shown by the diff with comments and blank lines
stripped.

## Leave alone

- `TOOLS.md` is generated (`bin/gen_tools_list.sh`); `KEYBINDINGS.md` is parsed
  by `bin/keys.sh`, so its tables keep their shape.
- `bin/mkworld.sh` and `bin/setup_homebrew.sh` stay self-contained: the macOS
  bootstrap job runs only when a file on its `paths:` list changes, and a
  helper they sourced would sit outside that list.
- The human-only scripts `AGENTS.md` lists are never run by an agent, so a
  sweep cannot check a change to them.

## Speed

`./bin/speed_report.sh` measures zsh, nvim and tmux startup, the hooks,
pre-commit and the bats suite in a hermetic HOME, and prints one row. The row
goes on issue #392 as one comment per run, numbers only: the repo is public.
Run it on `main`: on a branch, a SessionStart hook calls the network and the
numbers wobble. The budgets are those of `claudecode/rules/latency.md`.

In a cloud container:

- Put the mise shims at the end of `PATH`. First on `PATH`, the gitleaks shim
  fails under the bats temp HOME and the suite reads as failed.
- A changed HOME breaks the mise shims (config trust); install nvim, sheldon
  and starship with `mise use -g aqua:...`.
- tmux 3.4's `kill-server` returns before the server is gone, so use a new
  socket name per run.
- Never pass extra arguments to an `ln -sf` that names `/dev/null`: it once
  replaced `/dev/null`.

Per-test times for the inventory: `bats --timing test/`. Never run to time
them: the bootstrap and install scripts (`mkworld.sh`, `mklink.sh`,
`rmworld.sh`, `setup_*`, `install_*`, `brew_*`, `link_claude_dir.sh`,
`refresh_cloud_session.sh`) and the human-only scripts `AGENTS.md` lists; they
change the machine, so only their tests are timed.

Decided against: inlining tpm plugins into `.tmux.conf` (#225, #402).
## Security audit

This repo is public, so findings go only to issues on the private
`kimoto/routines` repo. `./bin/setup_cloud_session.sh` installs gitleaks.

Pinned inputs beyond the lockfiles and the workflow `uses:` SHAs:

- zsh plugins by commit (`rev =` in `config/sheldon/plugins.toml`) and tmux
  plugins in `tmux-plugins.lock`, by choice since #430;
- the nvim plugin lockfile, `mise.toml` / `mise.lock`, and the Homebrew
  installer commit in `bin/setup_homebrew.sh`;
- downloads in the `bin/` install scripts.

Agent permissions also live in `claudecode/settings-*.json` and `codex/`.

`stable` is the branch machines may follow instead of `main`; it only moves to
a commit already on `main`, so it must stay an ancestor of `origin/main`.

## Decided against: refactor

- One regex for the three tmux version checks: their thresholds differ, and
  the e2e tests read `@tmux_3_8`.
- Merging the four float half-binds in `.tmux.conf`: tmux has no functions, and
  a script would add a fork per key press.
- Generating the tmux table of `KEYBINDINGS.md`: it groups keys and lists
  plugin and default keys that `list-keys -N` does not.
- Sharing the Brewfile pick between the brew scripts: no test checks which
  Brewfiles are chosen, so the change could not be shown to be a no-op.
- `setopt` and completion `zstyle` comments are rewritten to say the effect at
  the prompt, never deleted.

## Decided against: prune

- Kept: `.gdbinit` (used by hand), the `pbcopy`/`pbpaste` shims, `c`, `snip`,
  `egrep`, the `mysqlsh` config, and tpm.
- Pending the owner: unused `Brewfile.extra` tools (#458).
