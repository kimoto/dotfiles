## Dotfiles Agent Notes

Shared instructions for AI assistants in this repo. `CLAUDE.md` is a symlink to
this file — edit `AGENTS.md`, never break the symlink.

### What this repo is

Personal macOS/Linux dotfiles, symlinked into `$HOME` by `bin/mklink.sh`, tools
installed via Homebrew (`Brewfile.*`). It's also a CI-tested project: the same
`bin/` lint scripts run locally (lefthook) and in GitHub Actions — one source of
truth, so the two never diverge.

### Repository map

- `bin/` — install scripts + the `lint_*`/`check_*` toolchain (shared by CI and
  lefthook). Key scripts: `mkworld.sh` (full bootstrap), `mklink.sh` (symlinks,
  `rmworld.sh` reverses), `install_check_tools.sh` (pinned tool versions — bump
  here), `dotfiles_sync_check.sh` (dirty/unpushed startup reminder),
  `gen_tools_list.sh` (regenerates `TOOLS.md` from the Brewfiles),
  `brew_bundle_install.sh` (interactive one-shot Brewfile install — human-only,
  refuses to run without a terminal; never invoke it from an agent),
  `ci_zsh_loading_test.sh` / `ci_tmux_loading_test.sh`.
- `config/` — XDG configs symlinked to `~/.config` (nvim, ghostty, starship, …).
- Root dotfiles — `.zshrc`, `.tmux.conf`, `.vimrc`, `.gitconfig`, … into `$HOME`.
- `KEYBINDINGS.md` — layered keybinding reference (macOS → AeroSpace → Ghostty →
  tmux → zsh → nvim; upper layers intercept first). When you add, remove, or
  rebind a key anywhere (`.tmux.conf`, `config/ghostty`, AeroSpace, zsh,
  `config/nvim`), update it in the same PR.
- `Brewfile.{basic,common,macos,linux}` — Homebrew bundles, sorted A–Z per
  section (`check_brewfile_sort.sh`). Split rule: `basic` = anything the shell
  needs at load time (prompt, completion, plugin manager, eval-cache inlines,
  startup aliases/`LS_COLORS`) — litmus test: if removing it breaks
  `ci_zsh_loading_test.sh`/`ci_tmux_loading_test.sh`, it's `basic`; CI installs
  only `basic`. `common` = full-workstation tooling not required to start the
  shell. `macos`/`linux` = platform-specific additions.
- `TOOLS.md` — generated catalog of every installed tool, built from the
  `brew bundle dump --describe` comments in `Brewfile.*` by `gen_tools_list.sh`.
  Never hand-edit; run `./bin/gen_tools_list.sh` after touching a Brewfile
  (CI + lefthook run `--check` to enforce it stays in sync).
- `.github/workflows/ci.yml`, `lefthook.yml` — CI and its local mirror.
- `.claude/` (settings + web SessionStart hook), `.codex/skills/` (Codex skills).

### Hooks & CI

- lefthook runs the `bin/` checks on commit/push; CI runs the same. Reproduce a
  check locally exactly as CI does, e.g. `./bin/lint_shell.sh`.
- Commits follow Conventional Commits `type(scope): description`, type ∈ {feat,
  fix, chore, docs, refactor, ci, revert, test} (`test` = test-only changes).
- Bypass a hook with `--no-verify`. CI failures: `gh run view <id> --log-failed`.
- GitHub Actions `uses:` must be pinned to a full commit SHA, not a tag.
- Config files with a top-level `$schema` are validated against it
  (`lint_schema.sh`) — keep the key accurate.
- TDD: when adding or changing a test, prove it fails first (red), then make it
  pass (green) — never ship a test you've only seen pass. Break the thing under
  test (or the assertion) so the test actually fails for the expected reason,
  then revert and confirm green. Especially for the `ci_*_test.sh` e2e checks,
  where a typo'd assertion can silently pass forever.

### Conventions

- `~/.config` must be a symlink to this repo's `config/` (mklink backs up a real
  one first). Reason: macOS CI runners ship a real `~/.config` that blocks it.
- `.editorconfig` (enforced): ≤120 cols, no trailing whitespace, final newline.
  Indentation is advisory; Markdown is exempt from line length — don't hard-wrap.
- Zsh/CI: set `ZDOTDIR` to the repo root; skip `.zshrc` sections in CI via an env
  flag (e.g. `DOTFILES_NO_SYNC_CHECK`), not an early return.
- If `git commit -S` hangs: `export GPG_TTY=$(tty)` and check pinentry-mac.

### Interaction

- When offering the user a choice between options (next step, approach, where to
  put something), prefer the `AskUserQuestion` tool over free-text questions —
  use it whenever the options are discrete enough to enumerate.

### Branch & PR workflow

- Never commit/push to `main` — branch first: `git switch -c <type>/<short-desc>`.
  lefthook and GitHub branch protection both block it.
- One PR per change, prefer 1 commit; fill `.github/PULL_REQUEST_TEMPLATE.md`
  (Summary, Changes, Verification, checklist). Verification lists the actual
  steps taken, not the generic checklist. Use `gh pr edit --body-file`.
- An auto-created PR (web/remote) starts with an empty body — the template is
  only injected by the GitHub UI; backfill it from the template before anything.
- Claude Code auto-appends its PR-body / commit trailers — don't remove them.
- After creating a PR from a session that can receive PR events, subscribe to
  its activity (`subscribe_pr_activity`) right away without asking — watch CI
  and review comments and act on them until the PR is merged or closed.

### Language

"Respond in Japanese" applies to chat replies, not artifact content. Commits,
PRs, comments, and docs are file content — always English; chat stays Japanese.
