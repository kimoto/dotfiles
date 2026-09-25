# Cloud session scope

Only the `~/.claude` entries of these dotfiles are linked here. `bin/mklink.sh`
did not run, and this container has no Homebrew.

⚠️ **The shadowed-command table in `environment.md` does not apply.** `.zshrc` is
not linked, so `cat` is cat, `curl` is curl, `dig` is dig, `ls` is ls, and `>`
overwrites an existing file — there is no `setopt noclobber`. Read that table as
describing a workstation, not this machine. ★Its zsh note still holds: the Bash
tool runs zsh here, so an unquoted glob in an option value still dies with
`no matches found` before the command runs.

`eza`, `bat`, `curlie`, `doggo`, `starship` and the rest of `Brewfile.*` are not
installed. Reach for the system tool.

★ **Commits here are signed regardless of this repo's own `.gitconfig`.** The
harness's own `~/.gitconfig` (not this repo's — `mklink.sh` didn't run) sets
`gpg.format = ssh` with a working `gpg.ssh.program`, and that outranks
`gpg.program`. A fixture that wants to prove a commit *fails* to sign by
setting `gpg.program false` alone will instead sign successfully over SSH —
pin `gpg.format openpgp` locally too, or use `isolate_git_env`
(`bin/git_fixture_helpers.sh`), which disables signing outright regardless of
format.
