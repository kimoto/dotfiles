# Experiments

**Measure only enough to change the next decision.** Evidence has a cost. Do not buy confidence that cannot change what you do next.

★**Try the likely winner once before benchmarking it.** If one approach is strongly favored and one run shows a large improvement, take it and move on. Repeat or add a control only when noise could plausibly reverse the decision.

★**Search, don't sweep.** Choose each probe to eliminate as much uncertainty as possible. Exploit the structure of the search space: bisect a boundary, bracket an optimum, or sample widely when the shape is unknown. Do not enumerate values unless enumeration is actually cheaper.

⚠️ **Precision is bought on demand.** Start with the cheapest evidence. Add repetitions, controls, and statistical rigor only when the current evidence is too ambiguous for the decision at hand.

★**Give every experiment run a time limit — 10 seconds by default.** Go longer only with the reason written down before the run. Hitting the limit means change the method, not wait or repeat. ⚠️ Exempt: the wait is the work (`latency.md`). ★Cap the work too (tries, not seconds), so load on the machine cannot change the result.
