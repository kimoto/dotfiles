# Shared user instructions

Before starting work, read `~/.claude/CLAUDE.md` if it exists and apply its user instructions. Resolve `~` to the current host's user home, including on Windows.

Also read Markdown files recursively under `~/.claude/rules/`, following linked rule directories. Claude loads those separately from `CLAUDE.md`; explicitly read them in Codex to share the same guidance. Apply rules with `paths` frontmatter only to matching files. If an instruction file refers to one already read, do not follow that reference again.

Interpret environment-specific guidance only where it applies: zsh aliases and options concern zsh sessions, and Claude tools, hooks, permissions, and UI features do not imply equivalent Codex capabilities or enforcement. Follow Codex's actual tool and permission instructions. Report missing or unreadable shared instruction sources instead of claiming they were loaded.

Repository instructions remain scoped to their repository. Do not load an unrelated repository's `CLAUDE.md` as global guidance.
