## Dotfiles Agent Notes

### CI triage
- Prefer `gh run view <run_id> --log-failed` to fetch failure logs quickly.
- Decide up front: "CI-only pass" vs "full CI environment parity".
- Keep CI checks minimal unless explicitly asked (default: starship + ls only).
- Avoid interactive-only checks in CI; use non-interactive substitutes when needed.

### ~/.config policy
- When setting up links, always back up a real `~/.config` and replace it with a symlink to this repo's `config/`.
- Reason: GitHub macOS runners already have a real `~/.config`, which prevents symlink replacement.

### Zsh/CI reproducibility
- When running CI zsh checks, explicitly set `ZDOTDIR` to the repo root to ensure the repo `.zshrc` is used.
- If CI requires skipping portions of `.zshrc`, prefer a dedicated flag or controlled environment variable over early returns.

### ShellCheck
- Always run `shellcheck bin/*.sh` (or the repo’s CI equivalent) after shell script edits.

### PR updates
- Use `gh pr edit --body-file` to avoid newline/markdown issues.
- Always include an AI disclosure line at the end of the PR body when requested.

### Commit signing
- If `git commit -S` hangs, run:
  - `export GPG_TTY=$(tty)`
  - Ensure pinentry is configured (macOS: pinentry-mac + gpg-agent.conf).
