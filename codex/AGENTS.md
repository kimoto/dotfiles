# Shared user instructions

Read Markdown files recursively under `~/.claude/rules/`, following linked rule directories. Claude loads these rules automatically; Codex must read them explicitly. Resolve `~` to the current host's user home, including on Windows.

Apply rules with `paths` frontmatter only to matching files. If an instruction file refers to one already read, do not follow that reference again.

Interpret environment-specific guidance only where it applies: zsh aliases and options concern zsh sessions, and Claude tools, hooks, permissions, and UI features do not imply equivalent Codex capabilities or enforcement. Follow Codex's actual tool and permission instructions.

Report unreadable rule sources, but do not treat an absent `~/.claude/CLAUDE.md` as an error.

Repository instructions remain scoped to their repository. Do not load an unrelated repository's `CLAUDE.md` as global guidance.
