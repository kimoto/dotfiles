# Security

**Allow, don't deny.** A list of what may pass is complete by construction;
a list of what must not pass is complete only until the next thing is added.
★Say next to each entry why it is there, so "still needed" and "nobody
removed it" can be told apart.

**A secret stays in the process that owns it.** Never in a URL or argv: a
failed command prints its argv into the traceback, and from there into
logs and transcripts. Pass it on stdin, in a 0600 file, or read it from
the keychain inside the process that uses it.
