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

## Git identity

⚠️ **A commit authored as whatever identity git falls back to may be a push
GitHub rejects, not a commit git rejects** — the failure surfaces only at
`git push`, after the work is already done:

```
remote: You can make your email public or disable this protection by visiting:
 ! [remote rejected] <branch> (push declined due to email privacy restrictions)
```

Recovery is worse than prevention: fixing it means `--amend --reset-author`,
the history rewrite that is off-limits once a branch might be shared.
Set the identity on the commit itself, before the first push on a branch:

```sh
command git -c user.name="<name>" -c user.email="<name>@users.noreply.github.com" commit -m ...
```

using the GitHub-issued noreply address for the account the branch pushes as
(visible on a prior commit that already pushed successfully, or in that
account's GitHub email settings) — an address git cannot verify is still one
GitHub accepts, since it already knows the address belongs to that account.
