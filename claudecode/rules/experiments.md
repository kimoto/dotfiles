# Experiments

**Measure only enough to change the next decision.** Evidence has a cost. Do not buy confidence that cannot change what you do next.

★**Try the likely winner once before benchmarking it.** If one approach is strongly favored and one run shows a large improvement, take it and move on. Repeat or add a control only when noise could plausibly reverse the decision.

★**Search, don't sweep.** Choose each probe to eliminate as much uncertainty as possible. Exploit the structure of the search space: bisect a boundary, bracket an optimum, or sample widely when the shape is unknown. Do not enumerate values unless enumeration is actually cheaper.

⚠️ **Precision is bought on demand.** Start with the cheapest evidence. Add repetitions, controls, and statistical rigor only when the current evidence is too ambiguous for the decision at hand.

★**Give every experiment run a time limit — 10 seconds by default.** ★A longer limit is fine when you write down why, next to the run, before it starts; an unstated reason does not count. ★When a run hits it, do not wait and do not add repetitions: treat it as the signal to change the method. One slow decoder turned out to be brute force; replacing it took a run from 100s to 1.6s, a change nobody would have looked for while waiting. ⚠️ Exempt: the wait is the work — a measurement window, physical motion, a transfer (`latency.md`); name which one applies, the same way. ★Give the tool a work limit too (tries, not seconds), so load on the machine cannot turn into a different result.
