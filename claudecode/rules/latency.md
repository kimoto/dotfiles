# Latency

**Anything a person waits on answers in under a second** — a command, a
keystroke, a click, a deferred or debounced action. The thresholds are human,
not technical, and have not moved in ~50 years (Nielsen): **0.1s** feels like
direct manipulation, **1s** keeps a train of thought unbroken, **10s** is where
attention leaves and progress must be shown.

⚠️ **When it cannot be met, write why next to the slow part.** Silence there
turns into "it has always been slow".

⚠️ **Exempt: the wait is the work, not a cost.** A measurement window
(`--seconds 20`), physical motion, a transfer or deploy. Read literally, this
rule otherwise argues for shortening a measurement window — which destroys the
measurement. Name which one applies.

⚠️ **A fast run may be a crashing run.** Check the exit code and the output
before calling it fast.
