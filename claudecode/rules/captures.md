# Captures

**Two things moving at once make a difference unattributable** — a parser you
broke and an input that moved look the same. So when producing the input is the
expensive or unrepeatable half — a radio packet, a tone that has to be played, a
device that has to be in the room — capture one and work against the capture.

★**Capture the raw bytes, before anything decodes them.** A capture your own
decoder already interpreted can only ever agree with it.

★**Record what the input really was, next to the capture.** Without that, a
correct decoder and a plausible one look identical: the meter's own screen read
2876 ppm, and the wrong byte order reads those same bytes as 13323.

⚠️ **Finish on the real thing.** A capture cannot show you what it did not catch.

⚠️ **Exempt:** anything code can regenerate in a second, identically. Generate it.
