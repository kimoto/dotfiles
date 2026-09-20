# Hooks

**CI is what decides whether a change is OK. Hooks run the same checks on your
own machine, earlier, so you hear about a problem before you push.** A hook can
be turned off with `--no-verify`, or never installed, so never assume one ran.
⚠️ Look in `.git/hooks/` yourself — an installer sitting in the repo is not the
same as an installed hook.

**Have hooks call the same scripts CI calls.** They run fewer of them, because
they have to be quick. But if you write a quick version of a check instead of
calling the real one, the two slowly stop agreeing, and both still say OK.

**How quick: under a second before a commit, under ten before a push** (the
numbers come from `latency.md`). ⚠️ Slower than that and people start typing
`--no-verify`, and then nothing runs at all. So the slower checks go before the
push — a commit only affects you, a push affects everyone.

★ **One check belongs before the commit anyway: scanning for secrets.** CI only
sees it after you push, and by then it is already in the history.

**Time hooks by CPU seconds, not by the wall clock.** The wall clock changes
with whatever else the machine is busy with, so a time limit set that way fails
for reasons that have nothing to do with your change. Add a time limit only if
you also bring the tool that applies it.
