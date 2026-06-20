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

### PR updates
- Use `gh pr edit --body-file` to avoid newline/markdown issues.
- Claude Code auto-appends `🤖 Generated with Claude Code` to PR bodies and `Co-Authored-By: Claude ...` to commits — do not remove these.
- Prefer 1 commit per PR. Write commit messages in English.

### Commit signing
- If `git commit -S` hangs: `export GPG_TTY=$(tty)` and ensure pinentry-mac is configured.
