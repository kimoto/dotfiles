# Environment

Quirks these dotfiles create on every machine. Machine-specific rules belong in another repo's `~/.claude/rules/` entry; project rules in that project's `CLAUDE.md`.

## Shadowed commands

`.zshrc` replaces these and the Bash tool inherits them. Use `command <cmd>`, which bypasses aliases *and* functions, or an absolute path.

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

Checked harmless: `grep`/`egrep`/`fgrep`, `mkdir`, `mv`.

## `setopt noclobber`

`>` onto an existing file fails with `file exists:`. It fails quietly mid-pipeline and the old content survives, so a later check reads the unchanged file as "the edit wasn't needed" rather than "the edit was lost". Use `>|`, or write a temp file and `cp`.

## zsh expands unquoted option values

`--include=*.ts` dies with `no matches found` before the command runs. Quote glob patterns passed as option values.
