# Git

**Commits follow Conventional Commits, `type(scope): description`**, type ∈
{feat, fix, chore, docs, refactor, ci, revert, test}; `test` is a change to
tests alone. ★A repo that names its own types or format wins.

**Never commit to the default branch — branch first**, `git switch -c
<type>/<short-desc>`, or whatever naming the repo asks for.

★**Work in your own worktree** (`claude --worktree`, or EnterWorktree), not the
main checkout: other sessions share it. ⚠️ Not one reached by `cd` in Bash —
Bash resets its directory after every command, so the session never leaves the
main checkout.

**Scan the range the PR introduces, not the working tree.**
`gitleaks git --log-opts "origin/<base>..HEAD"`. ⚠️ `<base>` is whatever branch
the PR targets. Pinned to `main`, the range drifts from what is actually under
review, and a clean result stops being evidence about this change.

**A leftovers reminder asks for an action, not a status line.** Uncommitted work
alone: commit it and stay quiet. ★Speak up only for something unpushed —
committing is local and reversible, publishing is neither.
