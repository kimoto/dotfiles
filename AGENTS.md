## Dotfiles Agent Notes

Shared instructions for AI assistants in this repo. `CLAUDE.md` is a symlink to
this file — edit `AGENTS.md`, never break the symlink. This file is an index:
every session reads all of it, so the why of each entry lives in the file the
entry points at (`bin/check_agents_size.sh` caps the size).

### What this repo is

Personal macOS/Linux dotfiles, symlinked into `$HOME` by `bin/mklink.sh`, tools
installed via Homebrew (`Brewfile.*`). The same `bin/` lint scripts run locally
(lefthook) and in GitHub Actions — one source of truth, so the two never diverge.

### Repository map

Each script's header says what it is for and why it is shaped that way; read it
before changing or calling the script.

- `bin/` — install scripts and the `lint_*`/`check_*` toolchain (CI + lefthook).
  Bootstrap: `mkworld.sh` (climbs the phases in `docs/staged-bootstrap.md`),
  `mklink.sh` / `rmworld.sh`, `install_check_tools.sh`, `setup_agent.sh` (any
  agent container), `setup_cloud_session.sh` (a container on this repo),
  `link_claude_dir.sh`, `refresh_cloud_session.sh`. Startup reminders: `dotfiles_sync_check.sh`,
  `brew_bundle_check.sh`, `mise_missing_check.sh`. Generated files:
  `gen_tools_list.sh` (`TOOLS.md`), `keys.sh` (reads `KEYBINDINGS.md`).
  Human-only, never from an agent: `brew_bundle_install.sh`,
  `check_cloned_repo_hooks.sh`, and the repo-root `vscode/install_vscode.sh`.
- `config/` — XDG configs symlinked to `~/.config` (nvim, ghostty, starship, …).
- `claudecode/` — Claude Code user configuration (rules, skills, settings).
  What belongs where: `claudecode/README.md`.
- `codex/`, `.codex/skills/` — Codex user defaults and the shared skills
  (`.claude/skills/<name>/SKILL.md` symlinks to the `.codex/` copy). See
  `codex/README.md`.
- `.claude/settings.json`, `.claude/hooks/` — this repo's Claude Code hooks and
  the allow-list for the read-only check toolchain. Each hook's header says
  what it does and what it never does. `git-leftovers-reminder.sh` is the
  exception: registered per machine, not by this file.
- Root dotfiles — `.zshrc`, `.tmux.conf`, `.vimrc`, `.gitconfig`, … into `$HOME`.
- `local.example/` — what goes in each `~/*.local` file those source last; the
  files themselves stay on the machine.
- `windows/` — the Windows half of the same workstation; manual copies, nothing
  in `bin/` reads it. See `windows/README.md`.
- `KEYBINDINGS.md` — layered keybinding reference (macOS → AeroSpace → Ghostty →
  tmux → zsh → nvim). Update it in the same PR as any binding change. It is
  data: `bin/keys.sh` parses its tables, so keep the table shape and headings.
- `mise.toml` / `mise.lock` — the pinned check toolchain on every platform;
  Renovate bumps it monthly. A bump needs `mise lock` in the same PR.
- `Brewfile.{standard,extra,macos,linux}` — Homebrew bundles, sorted A–Z per
  section. Where a tool goes: `docs/staged-bootstrap.md`.
- `TOOLS.md` — generated from the Brewfiles. Never hand-edit; run
  `./bin/gen_tools_list.sh` after touching a Brewfile.
- `docs/` — design notes: why, and the change list. A note whose work is built
  stays as the reference for that behaviour (`staged-bootstrap.md` is one).
- `test/` — bats unit tests. `test/e2e/` holds the end-to-end checks CI runs
  against a real shell/tmux/vim; `test/fixtures/` what they need but do not
  test. `ci/` is CI-only plumbing (prepare, bench, caches).
- `.github/workflows/ci.yml`, `lefthook.yml` — CI and its local mirror. ⚠️ The
  local half only exists where `lefthook install` ran.

### Hooks & CI

- lefthook runs the `bin/` checks on commit/push; CI runs the same. Reproduce a
  check locally exactly as CI does, e.g. `./bin/lint_shell.sh`.
- GitHub Actions `uses:` must be pinned to a full commit SHA, not a tag.
- Config files with a top-level `$schema` are validated against it
  (`lint_schema.sh`) — keep the key accurate.
- Red before green matters most for the `test/e2e/` checks, where a typo'd
  assertion can silently pass forever.

### Conventions

- `~/.config` must be a symlink to this repo's `config/` (mklink backs up a real
  one first).
- `.editorconfig` (enforced): ≤120 cols, no trailing whitespace, final newline.
  Indentation is advisory; Markdown is exempt from line length — don't hard-wrap.
- Zsh/CI: set `ZDOTDIR` to the repo root; skip `.zshrc` sections in CI via an env
  flag (e.g. `DOTFILES_NO_SYNC_CHECK`), not an early return.

### Branch & PR workflow

The flow is in the shared rules (`claudecode/rules/git.md`, `pull-requests.md`);
here it is enforced: lefthook and branch protection block a commit to `main`,
and a hook refuses a worktree reached by `cd`. A routine's PR (label
`routine:<name>`) follows `docs/routine-prs.md`.

### Language

"Respond in Japanese" applies to chat replies, not artifact content. Commits,
PRs, comments, and docs are file content — always English; chat stays Japanese.

## Scouts

Read by the sweep skills (`claudecode/skills/*-sweep`), `bottleneck-sweep`,
`security-audit` and `trend-intake`; the why, and the calls already made, are
in `docs/scouts.md`.

- Checks: `./bin/run_tests.sh` and `lefthook run pre-commit --all-files`.
- Proof of no change: `./bin/behavior_snapshot.sh compare origin/main`. Plugin
  config is outside it.
- Test gaps: `bin/mutation_sweep.sh` (also lists files no test selects). How a
  new e2e check gets run: `docs/scouts.md`.
- Leave alone: `TOOLS.md`, the `KEYBINDINGS.md` table shape, and the self-contained
  `bin/mkworld.sh` / `bin/setup_homebrew.sh`.
- Speed: `./bin/speed_report.sh` on `main`, one comment per run on #392; scripts
  never run to time are in `docs/scouts.md`.
- Security audit: findings go only to the private tracker the routine's prompt
  names; what is pinned where, and the `stable` branch, are in `docs/scouts.md`.
- Trends: the ledger, and where to read what is in use, are in `docs/scouts.md`.
- Commits and PRs: `docs/routine-prs.md` (it holds the open PR cap). The author
  comes from `.gitconfig.agent`; if your commit's is not kimoto, say so.
- Decided against: see `docs/scouts.md`.
