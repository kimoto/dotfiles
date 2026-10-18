# Claude Code user configuration

What `bin/mklink.sh` (and `bin/link_claude_dir.sh` in a container) links into
`~/.claude`. The directory is not named `claude/`: that is too close to this
repo's own `.claude/`, and with `core.excludesfile = ~/.gitignore` a `claude/*`
ignore rule would apply in every repo on the machine.

## What goes where

- `rules/` — linked as `~/.claude/rules/dotfiles`. Every `.md` under
  `~/.claude/rules/` loads into every session on the machine, so a rule costs
  every session. A rule belongs here when it holds on every machine regardless
  of what is being built: a quirk this setup creates (shadowed commands, zsh
  options that change redirects), or a standing judgement short enough that
  always loading it costs nothing. No frontmatter needed; add `paths:` only to
  scope a rule to matching files. ⚠️ Rules are acted on by the session that
  reads them; guidance for the person supervising it costs every session and
  moves none — that goes to the person, or to an issue, never here.
  Machine-specific rules go in another repo's own `~/.claude/rules/` entry
  (the directory is a conf.d), project-specific ones in that project's
  `CLAUDE.md`. `.gitignore` allow-lists each file so a rule another repo links
  in can never be committed here by accident.
- `skills/` — linked one by one as `~/.claude/skills/<name>`. A skill costs only
  the session that invokes it, so anything procedural belongs here rather than
  in `rules/`. Written in Japanese, against the language rule in `AGENTS.md`:
  the `description` is matched against requests that arrive in Japanese, and a
  skill is also read by the person deciding whether it says the right thing.
- `rules-cloud/` — linked as `~/.claude/rules/dotfiles-cloud` only by
  `link_claude_dir.sh --cloud`. It says what a container lacks, so every line
  is false on a workstation; `mklink.sh` removes the link.
- `settings-cloud.json` — `~/.claude/settings.json` for a cloud session,
  whichever repo it opened. Its `ask` rules on the rule files are the gate for
  unattended routines: a rule edit must stop at a prompt nobody answers there,
  while a person in a web session just approves it. ⚠️ Not a wall: a Bash write
  does not match an `Edit(...)` rule. Its `SessionStart` hook fast-forwards the
  checkout it is linked from and re-runs `link_claude_dir.sh --cloud`, because a
  cloud environment restores the setup script's result from a cache and would
  otherwise read stale rules and never see a skill added since. Its
  `UserPromptSubmit` hook is the context notice `mkworld.sh` registers on a
  workstation (`bin/claude_context_check.sh`), reached through the same link
  because a container never runs `mkworld.sh`.
- `settings-shared.json` — the keys of a workstation's `~/.claude/settings.json`
  that should match on every machine (status line, plugins, compaction).
  `bin/install_claude_settings.sh --sync` keeps the two in step per key on every
  shell start and in `mkworld`. The rest of that file stays the machine's: it
  holds what a public repo must not.
- `claude-hud/config.json` — claude-hud's look. `/claude-hud:configure` edits
  this file, not a copy.
