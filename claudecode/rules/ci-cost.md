# CI cost

**In a private repo, every Actions job is billed rounded up to a whole
minute.** A 5-second check costs 1 minute; six 30-second jobs cost 6 where one
3-minute job costs 3. Public repos are free. The plan includes 3,000 minutes a
month, and Sep 2026 went over by agents splitting checks and pushing each
commit.

★**Merge short jobs; do not split them for tidiness.** Split only when the
parallel wall time is worth the extra minutes, and say so in the workflow.

★**Give `push` triggers `paths:` when the check only reads a few files**, and
every job a `timeout-minutes` — the default is 6 hours, 12% of the month in
one hung job.

⚠️ **Before adding a workflow or a job to a private repo**, check the bill it
joins: `bin/gh_actions_cost.sh forecast` in the dotfiles repo, and
`breakdown OWNER/REPO` for where the minutes go.
