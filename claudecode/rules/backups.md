# Backups

**Size each backup by two questions: would a leak hurt, and could it be made
again?** One bar for everything costs effort where nothing is at stake.

- **Always**: record the sha256, download it back, compare. An upload that
  exited 0 proves nothing about what was stored.
- ★**A leak would hurt** (secrets, keys, personal data) → encrypt with
  `age -r` before it leaves the machine. Trust no provider. The private key
  lives on the owner's machine and in a password manager, never beside the
  backup.
- ★**It cannot be made again** → restore it into an empty instance on a
  schedule and compare counts; keep a second copy on the owner's machine.
- **It can be made again** → don't back it up; check the source still exists.

⚠️ Never store a store's credential inside that store.

Each backup gets one line in its repo's inventory: what, where, which case,
how verified, how long kept.
