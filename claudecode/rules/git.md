# Git

**Scan the range the PR introduces, not the working tree.**
`gitleaks git --log-opts "origin/<base>..HEAD"`. ⚠️ `<base>` is whatever branch
the PR targets. Pinned to `main`, the range drifts from what is actually under
review, and a clean result stops being evidence about this change.

**A leftovers reminder asks for an action, not a status line.** Uncommitted work
alone: commit it and stay quiet. ★Speak up only for something unpushed —
committing is local and reversible, publishing is neither.
