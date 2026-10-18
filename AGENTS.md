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
  `link_claude_dir.sh`. Startup reminders: `dotfiles_sync_check.sh`,
  `brew_bundle_check.sh`, `mise_missing_check.sh`. Generated files:
  `gen_tools_list.sh` (`TOOLS.md`), `keys.sh` (reads `KEYBINDINGS.md`).
  Human-only, never from an agent: `brew_bundle_install.sh`,
  `check_cloned_repo_hooks.sh`, `vscode/install_vscode.sh`.
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
- Commits follow Conventional Commits `type(scope): description`, type ∈ {feat,
  fix, chore, docs, refactor, ci, revert, test} (`test` = test-only changes).
- Bypass a hook with `--no-verify`. CI failures: `gh run view <id> --log-failed`.
- GitHub Actions `uses:` must be pinned to a full commit SHA, not a tag.
- Config files with a top-level `$schema` are validated against it
  (`lint_schema.sh`) — keep the key accurate.
- TDD: when adding or changing a test, see it fail first (red), then pass.
  Especially for the `test/e2e/` checks, where a typo'd assertion can
  silently pass forever.

### Conventions

- `~/.config` must be a symlink to this repo's `config/` (mklink backs up a real
  one first).
- `.editorconfig` (enforced): ≤120 cols, no trailing whitespace, final newline.
  Indentation is advisory; Markdown is exempt from line length — don't hard-wrap.
- Zsh/CI: set `ZDOTDIR` to the repo root; skip `.zshrc` sections in CI via an env
  flag (e.g. `DOTFILES_NO_SYNC_CHECK`), not an early return.
- If `git commit -S` hangs: `export GPG_TTY=$(tty)` and check pinentry-mac.

### Interaction

- When offering the user a choice between options, prefer the `AskUserQuestion`
  tool over free-text questions whenever the options can be enumerated.

### Branch & PR workflow

- Never commit/push to `main` — branch first: `git switch -c <type>/<short-desc>`.
  lefthook and GitHub branch protection both block it.
- Work in your own worktree (`claude --worktree`, or the EnterWorktree tool), not
  in the main checkout: other sessions share it. ⚠️ Not one reached by `cd` in
  Bash — the session never leaves the main checkout. A hook refuses it.
- One PR per change, prefer 1 commit; fill `.github/PULL_REQUEST_TEMPLATE.md`
  with `gh pr edit --body-file`. How to write one is in the shared rules.
- An auto-created PR (web/remote) starts with an empty body; backfill it from
  the template before anything.
- Claude Code auto-appends its PR-body / commit trailers — don't remove them.
- After creating a PR from a session that can receive PR events, subscribe to
  its activity (`subscribe_pr_activity`) right away without asking.

### Language

"Respond in Japanese" applies to chat replies, not artifact content. Commits,
PRs, comments, and docs are file content — always English; chat stays Japanese.
