# Comments

**A comment that survives in a file earns its place by carrying intent that
outlives the change.** Everything else — what was tried, what moved, which
commit did it — goes in the commit message, already dated and attributed.

★**Open a file, and a block its name does not explain, with what it is for**,
in a line or two. The code shows that only to someone who has read all of it.
A file that cannot carry a comment — JSON, a generated file, data a script
parses — goes without.

★**A comment says what the code cannot.** A line that repeats a name or the
line below it goes, however true, a header included.

★**Say why a value is what it is**, above all when it equals the default and is
spelled out anyway. Without that line the next reader cannot tell a deliberate
pin from something nobody cleaned up, and deletes it.

⚠️ **Leave no trace of the removal.** `# removed: …`, `# was X before the
migration`, a commit SHA, the steps of a migration that already finished — each
reads as current context, and checking any of it means leaving the file.
