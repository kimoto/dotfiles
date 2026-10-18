# Secrets

**A secret never goes in argv or the environment.** Any local user sees argv
in `ps`, and the environment in `ps eww`. A failed command echoes its argv
into a traceback, and from there into logs and transcripts. ★Pass a secret on
stdin (`curl -K -`, `security … -w` as the last flag), in a 0600 file, or read
it from the OS keychain inside the process that uses it.

★**When a child tool wants a secret in a URL, put a relay in between.** Keep
the credential in the process that owns it. Hand the child only something
like `rtsp://127.0.0.1:<port>/stream`.

⚠️ **Write examples with placeholders, not variables.** Readers copy
`curl "…?token=$TOKEN"` exactly as written. Write `<token>` instead.

⚠️ **Enforce it with a pre-commit pattern check, not with prose.** Check the
shape of the code, not the value. Start the baseline at zero.
