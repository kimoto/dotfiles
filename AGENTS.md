## Dotfiles Agent Notes

### Hooks & CI
- Lefthook runs various checks on commit; CI mirrors the same checks.
- Commit messages must follow Conventional Commits: `type(scope): description` — type ∈ {feat, fix, chore, docs, refactor, ci}.
- For CI failures: `gh run view <run_id> --log-failed`.

### ~/.config policy
- Always replace a real `~/.config` with a symlink to this repo's `config/` (back it up first).
- Reason: GitHub macOS runners ship with a real `~/.config`, which blocks symlink creation.

### Zsh/CI reproducibility
- Set `ZDOTDIR` to the repo root when running CI zsh checks.
- To skip parts of `.zshrc` in CI, use a dedicated env flag — not an early return.

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
