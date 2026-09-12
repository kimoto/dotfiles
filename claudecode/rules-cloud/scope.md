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
