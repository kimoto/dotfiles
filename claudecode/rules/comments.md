# Comments

**A comment that survives in a file earns its place by carrying intent that
outlives the change.** Everything else — what was tried, what moved, which
commit did it — goes in the commit message, already dated and attributed.

★**Open a file with what it is for**, in a line or two. The code shows that
only to someone who has read all of it. A file that cannot carry a comment —
JSON, a generated file, data a script parses — goes without.

★**Inside it, say intent with a name first.** Name the variable, or pull the
block out into a well-named function; an `if` or a short block gets no comment.
Comment only what is complex or cannot be said in code. A line that repeats a
name or the line below it goes, however true.

★**A name says what a block does, not what it is for.** So a function whose
aim its name cannot carry, or a section too large to name in one word, opens
with a line on what it is trying to achieve — not the name again. This covers config
sections (`.zshrc`, `.tmux.conf`) that cannot be pulled out into a function.

★**Say why a value is what it is**, above all when it equals the default and is
spelled out anyway. Without that line the next reader cannot tell a deliberate
pin from something nobody cleaned up, and deletes it.

⚠️ **Leave no trace of the removal.** `# removed: …`, `# was X before the
migration`, a commit SHA, the steps of a migration that already finished — each
reads as current context, and checking any of it means leaving the file.
