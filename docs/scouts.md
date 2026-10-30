# Scouts

The `## Scouts` section of `AGENTS.md` is what the routine skills read for
this repo; `grep -l Scouts claudecode/skills/*/SKILL.md` lists them. Most of
them stop when the section is missing, so it stays even when nothing below
changes. This note holds the why of each line there, and the calls already
made, so a sweep does not propose them again: the `Decided against` sections
are the decision ledger of `docs/routine-prs.md`.

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

## Test gaps

`bin/mutation_sweep.sh` flips each `exit 1` / `return 1` to 0 and runs the
bats files `bin/run_tests.sh` selects for that script; a survivor is a failure
exit no test watches. It skips guards after `cd`, and prints `untested <file>`
for a script no bats file selects. It edits files in place, so run it in its
own worktree.

An e2e check is a script in `test/e2e/` that drives a real zsh, tmux or vim;
the tmux ones share `test/e2e/tmux_e2e_helpers.sh`. CI runs each one by name:
a tmux check from the list in `ci/tmux_suite.sh`, the others from a step in
`.github/workflows/ci.yml`. A new file left off both never runs.
`hammerspoon_translate_test.sh` is left off on purpose: it drives the Mac's
own GUI and pays for real translations, so it runs by hand on a Mac.

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

How often a typed helper is used lives only in the owner's zsh history, on
their machine. `bin/usage_report.sh` reads it there, but the history keeps one
entry per command, so it gives the last use, not a count: a sweep can say
"used this week", never "used 40 times".

Decided against: inlining tpm plugins into `.tmux.conf` (#225, #402).
## Trends

The `trend-intake` ledger lives outside the repo, at
`/mnt/project-files/trends/ledger.md` in the Claude Project, because it holds
upstream risks this public repo must not publish. Run without the Project, it
goes without one.

What is in use: `Brewfile.*`, `mise.toml`, the tools under `config/`, the zsh
and tmux plugin lists, and `claudecode/` and `codex/`. A pick is something that
changes everyday work at the prompt or in the editor. A third-party tool is
pinned by commit SHA or a `mise.toml` version.

## Security audit

This repo is public, so findings go only to the private issue tracker the
routine's prompt names, never to this repo. The name stays out of here for the
same reason. `./bin/setup_cloud_session.sh` installs gitleaks.

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
- Kept: `.public_key.asc`, published so others can encrypt to the owner and
  check it is them; nothing in the repo reads it, by design (#559).
- Pending the owner: unused `Brewfile.extra` tools (#458). The toys (cowsay,
  figlet, fortune, lolcat) are gone; the rest wait on the shell history check.

## Decided against: features

- mergiraf as the merge driver (#478): replaying past merges, it resolved 4 of
  36 conflicted files; most conflicts here are edits to the same paragraph of
  prose or shell config.
- A prompt guard that blocks the `curl … | sh` spelling (#294): the risk is
  any fetched content reaching any interpreter, and one pattern only hides it.
- A Raycast Script Command for the note rewrite (#580): registering its folder is a
  manual step in Raycast's settings, and ⌃⌘⇧W already reaches the same script.
- A macOS CI e2e that drives the Hammerspoon popup with real keys (2026-10-28): the
  owner deferred it; whether the runner can grant Accessibility is untried, and
  `test/translate_menu.bats` covers the wiring.
