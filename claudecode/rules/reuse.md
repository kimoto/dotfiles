# Reuse

**Before writing a helper, look for the one that already does it.** Search by
what it does — the command it runs, the file it reads — not by the name you were
about to give it; the existing one was named by someone else. A second copy
works on the day it lands and drifts after, and nothing reports the drift.

★**Take what is already there, in this order: this repo's own helper, the
platform's built-in, the standard library.** A new dependency or a hand-built
version comes last, and the PR says why the ones before it did not fit.

⚠️ **Small is the result, not the goal.** Never cut validation, error handling or
a test to make a change shorter.
