# Environment

Quirks these dotfiles create on every machine. Machine-specific rules belong in another repo's `~/.claude/rules/` entry; project rules in that project's `CLAUDE.md`.

## Shadowed commands

`.zshrc` replaces these where the tool is installed, and the Bash tool inherits them. Use `command <cmd>`, which bypasses aliases *and* functions, or an absolute path. ⚠️ Where it is not — a container, a machine mid-bootstrap — the real command runs, so neither state is safe to assume.

| Typed | Actually | Symptom |
|---|---|---|
| `curl` | curlie | flag values parsed as data — GET turns into POST; `-sI` prints nothing |
| `cat` | bat | `cat -v` → `unexpected argument` |
| `ls` | eza — a **function**, so `alias ls` shows nothing | `ls -t f` → `invalid value for --time` |
| `ping` | gping | `ping -c 5 <host>` → usage text, no ping |
| ★`dig` | doggo | ⚠️**Wrong answer, not an error.** `dig +short <host>` queries the literal host `+short` → root SOA with `STATUS: NXDOMAIN`, which reads as "DNS is down". No `+time=`/`+tries=`, no `;; Query time:` line. |
| `cd` | z (zoxide) | a bare name that isn't a subdirectory jumps to a remembered directory, exit 0 |
| `less` | `bat --pager=less` | |
| `top` | btop | |
| `cp` | `cp -v` | |
| `vi` | nvim | |
| `w` | a **function** | |
| ★`git` | a **function**: `push` is shown to `bin/check_public_push.sh` first | a push to a **public** GitHub remote stops with `PUBLIC: <owner>/<repo>` and exits 1 — nothing is sent. Private remotes and every other subcommand are untouched. ⚠️ With no terminal (every agent session) it refuses instead of asking, by design: publishing is the one git operation with no undo, so it is a person's call. |

Checked harmless: `grep`/`egrep`/`fgrep`, `mkdir`, `mv`.

## `setopt noclobber`

`>` onto an existing file fails with `file exists:`. It fails quietly mid-pipeline and the old content survives, so a later check reads the unchanged file as "the edit wasn't needed" rather than "the edit was lost". Use `>|`, or write a temp file and `cp`.

★**`>>` is the mirror image: it fails when the file does *not* exist** (`no such file or directory`), so appending to a fresh log, or to one a `rm -f` just removed, dies on the first write. ⚠️ In a loop that redirects stderr to that same target, every error lands in the file that was never created — the loop finishes silently and reports success. Use `>>|`, or create it first with `: >| file`.

## zsh expands unquoted option values

`--include=*.ts` dies with `no matches found` before the command runs. Quote glob patterns passed as option values.
