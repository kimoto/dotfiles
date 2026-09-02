## Dotfiles Agent Notes

Shared instructions for AI assistants in this repo. `CLAUDE.md` is a symlink to
this file — edit `AGENTS.md`, never break the symlink.

### What this repo is

Personal macOS/Linux dotfiles, symlinked into `$HOME` by `bin/mklink.sh`, tools
installed via Homebrew (`Brewfile.*`). It's also a CI-tested project: the same
`bin/` lint scripts run locally (lefthook) and in GitHub Actions — one source of
truth, so the two never diverge.

### Repository map

- `bin/` — install scripts + the `lint_*`/`check_*` toolchain (shared by CI and
  lefthook). Key scripts: `mkworld.sh` (full bootstrap), `mklink.sh` (symlinks,
  `rmworld.sh` reverses), `link_claudecode.sh` (the `~/.claude` half of
  `mklink.sh`, split out so a cloud environment can run it alone — see **Cloud
  environments** below; it writes nothing outside `~/.claude`, and a test holds
  that line), `install_check_tools.sh` (pinned tool versions — bump
  here), `dotfiles_sync_check.sh` (dirty/unpushed startup reminder),
  `gen_tools_list.sh` (regenerates `TOOLS.md` from the Brewfiles),
  `claude_idle_recap.sh` + `install_claude_idle_hooks.sh` (on the first prompt
  after a long absence, tell the model the reader lost the thread — it opens
  with the problem instead of a diff; see `claudecode/skills/session-resume`).
  ⚠️ The gap is measured from the end of the last assistant turn, never wall
  clock: a 40-minute tool run leaves the same hole as someone leaving the desk,
  and only one of those is an absence. ⚠️ Nothing fires when a person merely
  looks at a terminal that stayed open — Claude Code has no such event — so the
  notice rides the first prompt after the gap,
  `keys.sh` (the keybinding cheatsheet picker behind zsh's `keys`/`⌃+X ?` and
  tmux's `prefix + ?` — it reads `KEYBINDINGS.md`, so adding a row there is what
  makes a binding discoverable),
  `brew_bundle_install.sh` (interactive one-shot Brewfile install — human-only,
  refuses to run without a terminal; never invoke it from an agent),
  `ci_zsh_loading_test.sh` / `ci_tmux_loading_test.sh`.
- `config/` — XDG configs symlinked to `~/.config` (nvim, ghostty, starship, …).
- `claudecode/rules/` — Claude Code user rules, linked in as
  `~/.claude/rules/dotfiles`. Every `.md` under `~/.claude/rules/` loads into
  every session on the machine; no frontmatter needed (add `paths:` only to
  scope a rule to matching files). A rule belongs here when it holds on every
  machine regardless of what is being built: a quirk this setup creates — shell
  aliases and functions that shadow standard commands, zsh options that change
  how redirects behave — or a standing judgement short enough that always
  loading it costs nothing.
  Machine-specific instructions go in another repo's own `~/.claude/rules/`
  entry; project-specific ones go in that project's `CLAUDE.md`. It is a conf.d: each source repo links its
  own subdirectory into `~/.claude/rules/`, so another repo can keep its rules
  there without this one ever seeing them — which is why mklink/rmworld touch
  only our own entry, and why `claudecode/rules/` is an allow-list in
  `.gitignore`. `~/.claude` itself is never symlinked: it also holds runtime state
  (transcripts, sessions, plugin caches). The directory name avoids `claude/`,
  which is both too close to this repo's own `.claude/` and, via
  `core.excludesfile = ~/.gitignore`, would make `claude/*` ignore rules apply
  in every repo on the machine.
- `claudecode/skills/` — Claude Code user skills, linked in one by one as
  `~/.claude/skills/<name>`. A rule costs every session; a skill costs only the
  session that invokes it, so anything procedural belongs here rather than in
  `rules/`. Two entries share a machine with skills other tools install, which
  is why the link is per skill and the `.gitignore` allow-list names each one.
  ⚠️ These are written in Japanese, against the language rule below, for two
  reasons: the `description` is what a request is matched against and the
  requests arrive in Japanese, and a skill is also read by the person deciding
  whether it says the right thing.
- `vscode/install_vscode.sh` — symlinks VS Code's live `settings.json`/
  `keybindings.json` to this repo (replacing any existing file) and
  installs/overwrites the `extensions` list. Manual, human-only setup step —
  not called from `mkworld.sh`, CI, or lefthook; never invoke it from an agent.
- Root dotfiles — `.zshrc`, `.tmux.conf`, `.vimrc`, `.gitconfig`, … into `$HOME`.
- `KEYBINDINGS.md` — layered keybinding reference (macOS → AeroSpace → Ghostty →
  tmux → zsh → nvim; upper layers intercept first). When you add, remove, or
  rebind a key anywhere (`.tmux.conf`, `config/ghostty`, AeroSpace, zsh,
  `config/nvim`), update it in the same PR. It is also data, not just docs:
  `bin/keys.sh` parses its tables into the on-demand cheatsheet, so keep the
  `| key | action |` table shape and the heading levels intact.
- `Brewfile.{basic,common,macos,linux}` — Homebrew bundles, sorted A–Z per
  section (`check_brewfile_sort.sh`). Split rule: `basic` = anything the shell
  needs at load time (prompt, completion, plugin manager, eval-cache inlines,
  startup aliases/`LS_COLORS`) — litmus test: if removing it breaks
  `ci_zsh_loading_test.sh`/`ci_tmux_loading_test.sh`, it's `basic`; CI installs
  only `basic`. `common` = full-workstation tooling not required to start the
  shell. `macos`/`linux` = platform-specific additions.
- `TOOLS.md` — generated catalog of every installed tool, built from the
  `brew bundle dump --describe` comments in `Brewfile.*` by `gen_tools_list.sh`.
  Never hand-edit; run `./bin/gen_tools_list.sh` after touching a Brewfile
  (CI + lefthook run `--check` to enforce it stays in sync).
- `test/fixtures/` — helpers the `ci_*_test.sh` e2e checks need but that are
  not themselves under test: `stub_lsp.py` is a language server that only
  completes the handshake, so CI can assert "opening a .ts file attaches a
  client" without installing a real one (which would test npm, not this repo).
- `.github/workflows/ci.yml`, `lefthook.yml` — CI and its local mirror.
- `.claude/settings.json` wires three hooks: `SessionStart` (`session-start.sh`,
  prepares the web sandbox), `SessionEnd` (`auto-main-sync.sh` — after a PR
  merges, switches back to `main`, pulls, and deletes the merged branch; a
  dirty tree, a still-open PR, or a linked worktree just prints a reminder
  instead — a worktree is told to remove itself, never switched to `main`), and
  `PostToolUse` on Bash (`pr-description-reminder.sh` — after a real `git push`,
  reminds to update the PR description to match what was just pushed; a command
  that only quotes a push stays silent). It also allow-lists the repo's own read-only check
  toolchain (`bin/lint_*.sh`, `bin/check_*.sh`, `bin/run_tests.sh`,
  `bin/ci_zsh_loading_test.sh`, `bin/ci_tmux_loading_test.sh`,
  `bin/gen_tools_list.sh --check`, `bats test/…`) so running a check the way CI
  runs it needs no prompt; anything that writes (`gen_tools_list.sh` without
  `--check`, `mklink.sh`, `brew bundle`) stays out.
- `.claude/hooks/git-leftovers-reminder.sh` — a `Stop` hook that reports how
  much is uncommitted, untracked, or unpushed as context the agent sees rather
  than output the user reads, and stays quiet until those counts change.
  Unlike every other hook here it is **not wired by `.claude/settings.json`**:
  it is registered per machine in `~/.claude/settings.json` and reached by a
  symlink nothing in `bin/` creates, so `mkworld.sh` installs the script
  without enabling it.
- `.codex/skills/` — the skills, and the single source for both agents:
  `.claude/skills/<name>/SKILL.md` is a symlink to the `.codex/` copy, so a skill
  is written once. A real directory holding a symlinked `SKILL.md` (not a
  symlinked directory) keeps discovery working regardless of how each agent
  walks the tree. `dotfiles-pr-flow` is deliberately Codex-only — it restates
  the PR rules Claude already reads from this file.

### Hooks & CI

- lefthook runs the `bin/` checks on commit/push; CI runs the same. Reproduce a
  check locally exactly as CI does, e.g. `./bin/lint_shell.sh`.
- Commits follow Conventional Commits `type(scope): description`, type ∈ {feat,
  fix, chore, docs, refactor, ci, revert, test} (`test` = test-only changes).
- Bypass a hook with `--no-verify`. CI failures: `gh run view <id> --log-failed`.
- GitHub Actions `uses:` must be pinned to a full commit SHA, not a tag.
- Config files with a top-level `$schema` are validated against it
  (`lint_schema.sh`) — keep the key accurate.
- TDD: when adding or changing a test, prove it fails first (red), then make it
  pass (green) — never ship a test you've only seen pass. Break the thing under
  test (or the assertion) so the test actually fails for the expected reason,
  then revert and confirm green. Especially for the `ci_*_test.sh` e2e checks,
  where a typo'd assertion can silently pass forever.

### Cloud environments (Claude Code on the web)

`~/.claude/rules/` and `~/.claude/skills/` do not exist in a cloud session, so
none of `claudecode/` applies there until something links it in. The vehicle is
the **environment's setup script** (the field in the environment dialog at
claude.ai/code): it runs before Claude Code launches, for every cloud session in
that environment, whichever repository is checked out.

```bash
#!/bin/bash
# rev 1 — bump this line to force a cache rebuild after changing claudecode/
git clone --depth 1 https://github.com/kimoto/dotfiles.git /opt/dotfiles || true
sh /opt/dotfiles/bin/link_claudecode.sh || true
```

⚠️ **Run `link_claudecode.sh`, never `mklink.sh`.** A cloud session's `$HOME` is
the platform's: `mklink.sh` would replace its `~/.gitconfig`, and every commit
and push in that session goes through the identity it holds.

⚠️ **The setup script runs once, then the filesystem is snapshotted and reused**
for about seven days, so the clone is frozen at snapshot time: a rule you push
today does not reach cloud sessions until the cache is rebuilt. Editing the
setup script is what rebuilds it — hence the `rev` line, which is there to be
bumped. There is no per-session refresh to fall back on: a cloud session runs
hooks from the repository it has open and from server-managed settings, and the
VM's own `~/.claude/settings.json` is not read.

### Conventions

- `~/.config` must be a symlink to this repo's `config/` (mklink backs up a real
  one first). Reason: macOS CI runners ship a real `~/.config` that blocks it.
- `.editorconfig` (enforced): ≤120 cols, no trailing whitespace, final newline.
  Indentation is advisory; Markdown is exempt from line length — don't hard-wrap.
- Zsh/CI: set `ZDOTDIR` to the repo root; skip `.zshrc` sections in CI via an env
  flag (e.g. `DOTFILES_NO_SYNC_CHECK`), not an early return.
- If `git commit -S` hangs: `export GPG_TTY=$(tty)` and check pinentry-mac.

### Interaction

- When offering the user a choice between options (next step, approach, where to
  put something), prefer the `AskUserQuestion` tool over free-text questions —
  use it whenever the options are discrete enough to enumerate.

### Branch & PR workflow

- Never commit/push to `main` — branch first: `git switch -c <type>/<short-desc>`.
  lefthook and GitHub branch protection both block it.
- One PR per change, prefer 1 commit; fill `.github/PULL_REQUEST_TEMPLATE.md`
  with `gh pr edit --body-file`. How to write one is in the shared rules.
- An auto-created PR (web/remote) starts with an empty body — the template is
  only injected by the GitHub UI; backfill it from the template before anything.
- Claude Code auto-appends its PR-body / commit trailers — don't remove them.
- After creating a PR from a session that can receive PR events, subscribe to
  its activity (`subscribe_pr_activity`) right away without asking — watch CI
  and review comments and act on them until the PR is merged or closed.

### Language

"Respond in Japanese" applies to chat replies, not artifact content. Commits,
PRs, comments, and docs are file content — always English; chat stays Japanese.
