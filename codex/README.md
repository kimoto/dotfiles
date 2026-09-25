# Codex user defaults

`config.toml` is the source for `~/.codex/config.toml`, not a project override in `.codex/config.toml`.

On macOS/Linux, `bin/mklink.sh` links this file when the destination is absent. Existing configurations (including foreign symlinks) are preserved; merge the two top-level values manually in that case. `bin/rmworld.sh` removes only the link pointing here. The rest of `~/.codex/` holds local state and is never linked.

On Windows, `windows/link_codex.ps1` merges these top-level values into `%USERPROFILE%\.codex\config.toml` before the first table header. It preserves all other top-level values plus desktop, plugin, MCP, and trust tables; it does not replace the entire file or use a WSL symlink. If `CODEX_HOME` is set, it uses that directory instead.

CLI flags and `--config` overrides, trusted project `.codex/config.toml` files, and selected profiles can override these user defaults. Existing tasks may retain their selected model and effort; check a new task after changing defaults.

See the [official configuration documentation](https://developers.openai.com/codex/config-basic/).

## Shared Claude instructions

`AGENTS.md` asks Codex to read the current host's `~/.claude/CLAUDE.md` and Markdown rules under `~/.claude/rules/`. These are explicit reading instructions, not a native Markdown import. Claude hooks, permissions, and tools are not installed or emulated by this bridge.

On macOS/Linux, `mklink.sh` links this bridge to `~/.codex/AGENTS.md` if absent and installs the repository's `CLAUDE.md` plus shared rules under `~/.claude/`. Cloud setup uses the same Claude linker. Existing instruction files are preserved; merge the shared guidance manually when a destination is already owned. `rmworld.sh` removes only this repository's links.

On Windows, run the setup script from the repository in PowerShell:

```powershell
./windows/link_codex.ps1 -WhatIf
./windows/link_codex.ps1
```

The script derives the checkout path from its own location and uses `USERPROFILE` for the Windows home and `CODEX_HOME` when set. It creates native Windows symlinks for `AGENTS.md` and `.claude/rules/dotfiles`, preserves existing destinations, and can be rerun. No username, drive, or WSL distribution name is embedded in the instructions or script. If Windows requires elevation, run the same script from an administrator PowerShell; it does not elevate itself.

Use `-SkipLinks` only when syncing the config on a machine that cannot create symlinks; a normal install should omit it so the shared instructions are installed too.

Windows execution policy may reject an unsigned script on a WSL UNC share even before link creation. In that case, use a trusted local Windows checkout or follow the machine's script-signing policy; this script does not change execution policy.

The checkout must remain available at that location. A WSL-hosted checkout is addressed through its Windows UNC path; Linux-created links under `/mnt/c` are not substitutes for native Windows links. Moving the checkout requires updating the links. The existing Claude user file and other rule directories remain local.

A non-empty `~/.codex/AGENTS.override.md` takes precedence over `AGENTS.md`. Start a new task after installing the bridge and ask it to list the instruction files it actually read. The repository-root `CLAUDE.md -> AGENTS.md` symlink is separate and must retain its direction to avoid a reference cycle.

## Cloud environments

Use `./bin/setup_cloud_session.sh` as the setup script for this repository's Codex cloud environment. The same entry point remains the Claude Code web setup: it installs the check toolchain and hooks, links the Claude rules and cloud-only guidance, and now also links `codex/config.toml` and the instruction bridge into `${CODEX_HOME:-$HOME/.codex}`. Existing destinations owned by another setup are preserved and reported as `MISS`.

Codex cloud environment setup is configured outside the repository, so checking in the script does not select it automatically. Set the environment's setup command to `./bin/setup_cloud_session.sh`; Codex invalidates its environment cache when that configured script changes.

## Path conventions

In instruction prose, `~` means the home of the host running the agent. Use `$HOME` in POSIX shell scripts and `$env:USERPROFILE` in Windows PowerShell when constructing home paths. Do not assume TOML values expand either notation. Use repository-relative paths for project files, and resolve setup sources relative to the setup script rather than the caller's working directory.

`bin/mklink.sh` and `bin/rmworld.sh` manage the standard `$HOME/.codex` location. For a custom `CODEX_HOME` on macOS/Linux, install the config and instruction links there manually.
