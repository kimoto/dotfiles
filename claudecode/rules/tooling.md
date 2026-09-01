# Tooling

**Ask the same question twice? Write the tool. It is not done until its test has
failed once.** Second time, not fifth.

1. **Give it a name.** A one-liner you paste from memory comes out a bit
   different every time, and none of those can be tested.
2. **Same input, same answer.** Move the decisions inside — which sensor to
   trust, what counts as too hot, when to stop. ★The script that calls it can
   be messy: it picks *when*, never *what*. ⚠️ The messy part holds the bugs
   and is the part you delete, so the bug is all that survives.
3. **Break it once and watch the test go red.** Put the bug back in, see it
   fail, take it out. ★A test that has only ever passed is a habit, not a check.

**Cannot see whether it worked? You are guessing.** ★Before you send anything,
pick what you will look at after — something that only moves if it really
happened. A fan spinning. A new row. ⚠️ Reading the setting back just shows what
you wrote.

⚠️ **Code that cannot tell "broken" from "fine" turns it up.** Nothing happening
looks like not enough happening. ★Check it worked first.

> A timer had switched an aircon off. Every call said OK, every setting read
> back right, nothing ran for 27 minutes. The room warmed up, the script called
> that under-cooling, and drove a dead machine to full power in an empty house.

**Finish it in one order: e2e, then units, then speed.**

- **e2e first — the whole thing, called the way it will really be called.**
  ★It is the only test that fails when every piece is right and the wiring is
  not. ⚠️ Written after the units, it can only confirm the shape you already
  picked.
- **Units next, on the parts the e2e made you name.**
- **Speed last, against a number you took before you touched it.** ★No
  before-number, no tuning: you cannot tell a win from a rewrite. The thresholds
  are in `latency.md`. ⚠️ Tuning ahead of the two above is not tuning, it is
  rewriting code nothing is watching.

⚠️ **Skip all this if the job ends when you get the answer** — a migration, a
bug hunt, poking around. Say which one. "This will be quick" is how you get the
second copy.
