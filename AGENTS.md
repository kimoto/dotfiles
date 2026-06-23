## Dotfiles Agent Notes

This file is the shared instruction set for AI assistants working in this repo.
`CLAUDE.md` is a symlink to this file, so Claude Code and Codex read the same
source — edit `AGENTS.md`, never break the symlink.

### What this repo is

Personal dotfiles for macOS and Linux. Configs live in the repo and are
symlinked into `$HOME` by `bin/mklink.sh`; tools are installed with Homebrew
(`Brewfile.*`). The repo doubles as its own CI-tested project: every shell
script, config file, and workflow is linted, and the same checks run locally
(lefthook) and in GitHub Actions from a single set of `bin/` scripts.

### Repository map

- `bin/` — install scripts and the lint/check toolchain (see below). Each
  `lint_*`/`check_*` script is the **single source of truth** shared by CI and
  the lefthook hooks, so the two never diverge.
  - `mkworld.sh` — full bootstrap: symlinks (`mklink.sh`), Homebrew
    (`setup_homebrew.sh`, skip with `SKIP_BREW=1`), tpm, and lefthook install.
  - `mklink.sh` — symlinks repo files/dirs into `$HOME` (backs up a real
    `~/.config` first). `rmworld.sh` reverses it.
  - `setup_homebrew.sh` / `setup_macosx.sh` — Homebrew + macOS defaults.
  - `install_check_tools.sh` — pinned lint toolchain (gitleaks, ratchet, yq,
    biome, …); the one place to bump versions. Used by CI and the web
    SessionStart hook.
  - `dotfiles_sync_check.sh` — shell-startup reminder when the repo is dirty /
    unpushed / behind. Skipped via `DOTFILES_NO_SYNC_CHECK=1`.
  - `ci_zsh_loading_test.sh` / `ci_tmux_loading_test.sh` — load `.zshrc` /
    `.tmux.conf` in a sandbox and assert they parse cleanly.
- `config/` — XDG configs symlinked to `~/.config` (nvim, ghostty, starship,
  k9s, lazygit, bat, gh, mise, sheldon, zsh-abbr, …).
- Root dotfiles — `.zshrc`, `.tmux.conf`, `.vimrc`, `.gitconfig`, `.inputrc`,
  `.aerospace.toml`, etc., symlinked directly into `$HOME`.
- `Brewfile.basic|common|macos|linux` — Homebrew bundles, split by scope/OS.
  Entries are kept sorted A–Z per section (enforced by `check_brewfile_sort.sh`).
- `hammerspoon/`, `mysqlsh/`, `vscode/` — app-specific configs.
- `.vim/bundle/neobundle.vim` — git submodule; clone with `--recursive`.
- `.github/workflows/ci.yml` — CI (static checks + zsh/tmux loading tests).
- `lefthook.yml` — local git hooks mirroring CI.
- `.claude/` — Claude Code settings + the web SessionStart hook.
- `.codex/skills/` — Codex skills (`dotfiles-pr-flow`, `dotfiles-recommender`).

### Hooks & CI
- Lefthook runs the `bin/` check scripts on commit/push; CI runs the same ones.
  Run a check locally exactly as CI does, e.g. `./bin/lint_shell.sh`.
- pre-commit: `protect-main`, `lint_shell`, `lint_zsh`, `lint_config`,
  `lint_schema`, `lint_editorconfig`, `lint_actions`, `check_brewfile_sort`,
  `check_secret_files`, gitleaks. pre-push: `protect-main`, full gitleaks.
- Commit messages must follow Conventional Commits: `type(scope): description`
  — type ∈ {feat, fix, chore, docs, refactor, ci, revert}. Enforced by the
  `commit-msg` hook.
- Bypass a hook intentionally with `--no-verify` (commit and push).
- For CI failures: `gh run view <run_id> --log-failed`.
- GitHub Actions `uses:` must be pinned to a full commit SHA (ratchet,
  `lint_actions.sh`), not a mutable tag.

### ~/.config policy
- Always replace a real `~/.config` with a symlink to this repo's `config/`
  (back it up first; `mklink.sh` does this automatically).
- Reason: GitHub macOS runners ship with a real `~/.config`, which blocks
  symlink creation.

### Zsh/CI reproducibility
- Set `ZDOTDIR` to the repo root when running CI zsh checks.
- To skip parts of `.zshrc` in CI, use a dedicated env flag (e.g.
  `DOTFILES_NO_SYNC_CHECK`) — not an early return.

### Editing conventions
- `.editorconfig` is enforced by `editorconfig-checker` (line length ≤120 by
  default, no trailing whitespace, final newline). Indentation is advisory
  only (checker's indentation rule is disabled). Markdown is exempt from line
  length — don't hard-wrap prose.
- Config files declaring a top-level `$schema` are validated against it
  (`lint_schema.sh`); keep that key accurate.

### Branch & PR workflow
- Never commit or push directly to `main`. Always branch: `git switch -c <type>/<short-desc>` (type ∈ feat|fix|chore|docs|refactor|ci).
- lefthook blocks direct commits/pushes to `main` (`protect-main` in pre-commit & pre-push); GitHub branch protection enforces it server-side too.
- Every change lands via a PR using `.github/PULL_REQUEST_TEMPLATE.md` — fill in Summary, Changes, Verification, and the checklist. The change type lives in the commit subject (Conventional Commits), not a template field.
- The Verification section must list the actual steps taken in the session (e.g. reloaded config, visually confirmed X), not just restate the generic checklist items.
- Keep PRs small: prefer 1 commit per PR; commit subject must satisfy the Conventional Commits check.

### PR updates
- Use `gh pr edit --body-file` to avoid newline/markdown issues.
- Claude Code auto-appends `🤖 Generated with Claude Code` to PR bodies and `Co-Authored-By: Claude ...` to commits — do not remove these.
- Prefer 1 commit per PR. Write commit messages in English.

### Language
- Public artifacts (commit messages, PR title/body, code comments, docs) are written in English — English is the de facto standard for published work.
- Chat/sessions with Claude are in Japanese.

### Commit signing
- If `git commit -S` hangs: `export GPG_TTY=$(tty)` and ensure pinentry-mac is configured.
