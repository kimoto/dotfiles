# Pull requests

★**Write only what the diff cannot say.** A reader should finish the body able
to ask "which lines?" and never "why?". Do not restate the changes: a filename
or a function in the body goes stale the moment the branch moves, and the diff
already shows it. The why stays even when a comment in the diff says it,
because reviewers read the body first. A human stops reading early, so add a
sub-bullet only when the reader needs it, and hide nothing behind `<details>`.
All of this holds for a commit body too.

★**As short as it can be: about 100 words is the ceiling, not the aim.**
Summary: what changes for the user in one sentence, then at most three bullets
of why. Verification: the list of names below. Leave out acceptance criteria,
red-first steps and what was tried; the commits hold those. When a push
changes the PR, update the body without letting it grow.

**A title carries the purpose and nothing else** — `type(scope): purpose`, about
50 characters, no script names, no jargon, no counts: a number means nothing
until the body says what it is scale of.

★**Name what checked the change** — a job, a hook, a command run by hand, in
one list. A name can be looked up; prose saying checks passed cannot. If
nothing checked it, say so plainly: that is the finding, and "none" hides it.

**Add a checklist box only for what no machine can check.** Every box ends up
ticked, so an empty one at merge cannot be told from an ignored one.

⚠️ **On a public repo, write nothing a stranger shouldn't read** — no repo they
cannot open, no server layout, nothing on where secrets live. Check the
visibility first: an edit does not unpublish.

**One PR per change, ideally one commit.** Fill the repo's PR template, if it
has one. An auto-created PR (web, remote) starts empty, so backfill it before
anything else. After creating a PR from a session that can receive PR events,
subscribe to its activity (`subscribe_pr_activity`) without asking.
