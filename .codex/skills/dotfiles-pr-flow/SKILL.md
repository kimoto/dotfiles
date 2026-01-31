---
name: dotfiles-pr-flow
description: Dotfiles pull request workflow from local changes through shellcheck, commit, push, and gh pr create. Use when preparing a PR for this dotfiles repo and you need the exact sequence and repo-specific rules from AGENTS.md.
---

# Dotfiles PR Flow

## Overview

Follow the repo-specific PR flow: create a branch if missing, make changes, run required checks, commit with rules, push, and open a PR with the required footer.

## Workflow

### 1) Confirm scope and repo rules

- Read `AGENTS.md` from the repo root and apply its PR, ShellCheck, and commit rules.
- Assume one commit per PR unless there is a clear reason to split.

### 2) Create a branch if missing

- If no branch exists yet, create one with a meaningful name.

### 3) Make changes

- Edit files as requested.
- Keep changes minimal and focused on the requested task.

### 4) Run required checks

- If any shell scripts under `bin/` changed, run:
  - `shellcheck bin/*.sh`
- Keep checks minimal unless explicitly asked to run more.

### 5) Commit (rules apply)

- Use an English commit message.
- If commit signing hangs, run:
  - `export GPG_TTY=$(tty)`
  - Ensure pinentry is configured (macOS: pinentry-mac + gpg-agent.conf).
- Example:
  - `git add <user-specified files>`
  - `git commit -m "<English summary>"`

### 6) Push

- Push the branch to origin:
  - `git push -u origin <branch>`

### 7) Create PR

- After committing, confirm with the user before creating a PR.
- Use `gh pr create` only after user confirmation.
- Include an AI disclosure footer at the end of the PR body by default.
  - Default line: `AI disclosure: Drafted with Codex.`
- Prefer `--body-file` to avoid newline/markdown issues.

Example PR body (ensure the AI disclosure line is last):

```
## Summary
- ...

## Testing
- ...

AI disclosure: Drafted with Codex.
```

If updating PR text later, use:
- `gh pr edit --body-file <file>`

## Notes

- If a user requests an AI disclosure in commit messages, add a final line in the commit message.
- Keep the flow linear: change -> shellcheck (if needed) -> commit -> push -> PR.
