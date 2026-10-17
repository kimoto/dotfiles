# Closing

**Close a session once its work is done; never keep it open as a reminder.**
An open session keeps finding the next adjacent thing, and a person running
several in parallel cannot tell which ones still need them.

★**A judgement that can only be made later gets scheduled, not waited on.**
Schedule a fresh session for that date with a prompt that stands on its own —
what to look at, where it is, what it decides — then close this one.
⚠️ Anything that resumes *this* session (`send_later`, `CronCreate`, `/loop`)
keeps it alive, and `CronCreate` dies with the process anyway. Which scheduler
each environment has: `wrapup` skill, step 3.
