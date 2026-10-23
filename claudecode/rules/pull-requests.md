# Pull requests

**Write only what the diff cannot say.** A reader should finish the body able to
ask "which lines?" and never "why?". Restating changes or naming files goes
stale the moment the branch moves; the diff is already there and is always
right. Same for a commit body. ★The diff includes its comments: a reason a
comment in it already gives does not go in the body again.

**A title carries the purpose and nothing else** — `type(scope): purpose`, about
50 characters, no script names, no jargon. ⚠️ **No counts either**: a number is
scale, and scale means nothing until the body says what it is scale of.

⚠️ **A line that opens with a filename, a function, or a step number has already
spent the reader's attention on "where"** — which the diff answers. Open with the
intent instead, one line per change. A human reads this and stops early, so keep it
short: add a sub-bullet only when the reader needs it, never for what the diff or
CI already shows. ★Nothing may hide behind `<details>`.

⚠️ **Name what checked the change** — a job, a hook, a command run by hand, in
one list. Asserting in prose that checks passed adds nothing and rots; a name
can be looked up. ★**Being unable to name anything is the finding**, and
"none" hides it behind a word that reads like a formality.

⚠️ **A checklist box only earns its place if no machine can take it over**, and
a box that survives is an admission that nothing automates it yet. What is left
is what the author is known to forget. Every box ends up ticked — one still
empty at merge cannot be told apart from one ignored.

★**On a public repo, write nothing a stranger shouldn't read** — no repo they
cannot open, no server layout, nothing on where secrets live. Check
`gh api repos/OWNER/REPO --jq .visibility` first: an edit does not unpublish.

**Turn on auto-merge at creation only when both hold: the session already
agreed to it, and the diff cannot change behavior** — comments, docs, or a
`refactor` whose tests did not change. Say in the reply that it is on, so the
merge is never a surprise. ⚠️ Anything else waits for a human to press it.
