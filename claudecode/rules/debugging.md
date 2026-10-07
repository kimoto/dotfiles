# Debugging

**A path that fails end to end tells you nothing until you know where it
stops.** Build the rung that must pass and the rung that must fail, and put
both through the real path — a rung that skips a stage cannot bracket that
stage.

★**The must-pass rung is the smallest real payload, not a local round trip.**
A round trip that never leaves the process agrees with itself by construction
and proves the codec, not the path.

⚠️ **One pass is a coincidence with a name.** The must-pass rung is not
established until it has passed enough times in a row to beat the effect size
you intend to measure — a control that is itself unreliable cannot tell you
when conditions drifted.

⚠️ **A probe with no failing end is not a probe.** Without one you cannot
tell "my probe is blind" from "everything passes."

Then bisect, one rung at a time, each on a clean environment first. A
leftover process still holding a shared resource makes every later reading a
fresh mystery — five sightings of "the system changed" can be one zombie.
