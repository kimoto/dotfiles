# Pull requests

**Write only what the diff cannot say.** A reader should finish the body able to
ask "which lines?" and never "why?". Restating changes or naming files goes
stale the moment the branch moves; the diff is already there and is always
right. Same for a commit body.

**A title carries the purpose and nothing else** — `type(scope): purpose`, about
50 characters, no script names, no jargon. ⚠️ **No counts either**: a number is
scale, and scale means nothing until the body says what it is scale of.

⚠️ **A line that opens with a filename, a function, or a step number has already
spent the reader's attention on "where"** — which the diff answers. Open with the
intent instead, one line per change, and refuse to hang before/after, evidence and
blast radius underneath as sub-bullets. ★The body is read top-down by someone who
will stop early, so nothing may hide behind `<details>`.

⚠️ **Name what checked the change** — a job, a hook, a command run by hand, in
one list. Asserting in prose that checks passed adds nothing and rots; a name
can be looked up. ★**Being unable to name anything is the finding**, and
"none" hides it behind a word that reads like a formality.

⚠️ **A checklist box only earns its place if no machine can take it over**, and
a box that survives is an admission that nothing automates it yet. What is left
is what the author is known to forget. Every box ends up ticked — one still
empty at merge cannot be told apart from one ignored.
