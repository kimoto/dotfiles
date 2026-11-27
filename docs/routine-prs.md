# Routine PRs: how they get merged

Scheduled agents ("routines", labelled `routine:<name>`) open most PRs here. The
owner reads a PR by its title first and opens the diff only when the title
worries them, so the PR itself has to say what kind of change it is and how
much reading it needs. This note is the source of truth for that; a routine's
own prompt only says "follow `docs/routine-prs.md`".

Every repo a routine works in gets the same label colours, set by
`bin/routine_labels.sh` (the skills run it before labelling), so a routine PR
looks the same wherever it is opened.

## Status

Every PR merges itself once the required checks pass, except class C. Open
it ready for review, not as a draft, and turn on squash auto-merge in the
same step: the required checks are the gate, and the owner does not read it.
Cloud sessions block GitHub GraphQL, so `gh pr merge --auto` fails there; use
the GitHub MCP `enable_pr_auto_merge` or the REST route
`PUT repos/<owner>/<repo>/pulls/<n>/ccr/auto_merge` instead.

⚠️ Do not turn a draft ready and arm auto-merge at once. A required job
skipped while the PR was a draft counts as passed, so the PR can merge before
the new run starts. Arm it only once that run shows up.

Never arm auto-merge, in any class, on a PR that publishes material from a
private source to a public site. Publishing cannot be undone.

Other repos set their own bar: where a repo's own instructions say how its
PRs merge, or forbid auto-merge for some of them, those win over this note.

The owner chose this on 2026-11-16, after the comment-only trial from
2026-10-31.

## Classes

**A — merges itself once checks pass**

- Comment- and blank-line-only changes: the diff with comments and blank lines
  stripped is empty.
- Version bumps and pins, when CI including the e2e set is green.
- Refactors whose behaviour snapshot (`bin/behavior_snapshot.sh`) diff is empty
  and whose touched area's e2e checks are green.

Never class A, even when the above holds: changes to `.github/workflows/`,
authentication or permissions, hook registration, and security fixes. Those
go to B or C by direction (below).

**B — merges itself once checks pass; the owner may skim the title afterwards**

- Adding a test or a check, wording fixes, removing something unused.
- New features (a new tool, binding, or default).
- Security or workflow changes that *tighten*: add a pin, a signature or
  checksum check, a timeout, or remove a permission.

**C — the owner reads the diff before it merges**

A class C PR carries one unticked box, `- [ ] Owner read the diff`. In this
repo the required `require-checklist` status then stays pending, holding the merge, until the
owner ticks it; elsewhere, leave auto-merge off.

- Security or workflow changes that *loosen*: widen a permission, drop a check,
  unpin, add a network fetch.
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
- At most 5 open class C routine PRs across all repos; PRs that merge
  themselves do not count. A routine that would go over opens nothing and says so in its
  report. More open PRs means less careful review.
- When the owner closes a routine PR unmerged, they leave a one-line reason as
  a comment.

## The decision ledger

The `Decided against` sections of `docs/scouts.md` hold the owner's calls, so
one routine's rejected direction is not proposed again by another. A close
reason seen only by the routine that opened the PR left the others free to
undo it.

- Before picking a change, a routine reads the ledger and the reasons on every
  closed-unmerged routine PR here, not only its own, and proposes nothing
  either one rules out.
- A reason not yet in the ledger becomes that run's one PR: the entry, class B,
  `cleanup`.
- A call the owner makes in a session goes into the ledger in the same PR as
  the change it decides.
- This repo is public: an entry says what was decided and why in terms a
  stranger may read, and links the PR (`#123`) instead of quoting a private one.
