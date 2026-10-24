# Routine PRs: how they get merged

Scheduled agents ("routines", labelled `routine:<name>`) open most PRs here. The
owner reads a PR by its title first and opens the diff only when the title
worries them, so the PR itself has to say what kind of change it is and how
much reading it needs. This note is the source of truth for that; a routine's
own prompt only says "follow `docs/routine-prs.md`".

## Status

Trial week (one week from the day the routine prompts start pointing here): routines add the `automerge:candidate` label to
class A PRs but do not merge anything. After the week, if the label matched the
owner's own calls, GitHub auto-merge is turned on for class A only.

## Classes

**A — may merge itself once checks pass** (during the trial: label only)

- Comment- and blank-line-only changes: the diff with comments and blank lines
  stripped is empty.
- Version bumps and pins, when CI including the e2e set is green.
- Refactors whose behaviour snapshot (`bin/behavior_snapshot.sh`) diff is empty
  and whose touched area's e2e checks are green.

Never class A, even when the above holds: changes to `.github/workflows/`,
authentication or permissions, hook registration, and security fixes. Those
go to B or C by direction (below).

**B — the owner merges on the title**

- Adding a test or a check, wording fixes, removing something unused.
- Security or workflow changes that *tighten*: add a pin, a signature or
  checksum check, a timeout, or remove a permission.

**C — the owner reads the diff**

- Security or workflow changes that *loosen*: widen a permission, drop a check,
  unpin, add a network fetch.
- New features (a new tool, binding, or default).
- Anything the routine itself is unsure about.

Telling tighten from loosen is a judgement, not a machine check, so the routine
states it, and writes `loosens` whenever it is unsure.

## The first line of the body

One short line in plain English, before the template:

```
What changes for you: <one sentence> · class <A|B|C> · <feel|speed|safety|plumbing|cleanup>[ · tightens|loosens]
```

- `feel` — something the owner notices in daily use; `speed` — a measured
  time goes down (give before/after); `safety` — pins and checks; `plumbing` —
  tests, CI, tooling with no visible change; `cleanup` — no behaviour change.
- `tightens`/`loosens` only for security or workflow changes.

## Limits

- Assign every routine PR to `kimoto`.
- At most 5 open routine PRs in class B or C across all repos; class A PRs do
  not count. A routine that would go over opens nothing and says so in its
  report. More open PRs means less careful review.
- When the owner closes a routine PR unmerged, they leave a one-line reason as
  a comment. Before picking a new change, a routine reads the reasons on its own
  closed-unmerged PRs and does not propose the same direction again.
