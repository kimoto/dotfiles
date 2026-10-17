# Backups

**How much a backup needs is set by two questions, not one bar for all:
would a leak hurt, and could the data be made again?** Every rule below says
which answer triggers it. Applying all of it to a regenerable public file is
cost with nothing bought; skipping it for secrets is the failure.

**Always, because it costs one line: record the sha256 when you make it, then
download it back and compare.** A finished upload proves the request ended,
not what was stored.

★**Would a leak hurt** (secrets, personal data, private keys, a DB with users
in it) → **encrypt before it leaves the machine that made it.** No storage
provider is trusted — not the bucket, the drive, or the CI that ships it.
Encrypt to a public key (`age -r`), so the job that writes a backup can never
read one. The private key lives in two places the backup does not: the
owner's machine and a password manager. ⚠️ Lose both and every backup is
noise.

★**Could it not be made again** (the only copy of a DB, photos, logs nobody
else kept) → **restore it on a schedule** into an empty instance and compare
row or file counts, and **keep it in two places, one the owner's own
machine.** A backup never restored is a hope; a provider can lock the account
and take the copy with it.

**Could it be made again** (a git repo with a remote, a build, a package) →
don't back it up; check now and then that the source still answers.

⚠️ **Never store the credential that opens a store inside that same store** —
when you lose it, it is locked in the place it opens.

**Every backup has one line in its repo's inventory**: what, where, which of
the answers above, how it is verified, how long it is kept.
