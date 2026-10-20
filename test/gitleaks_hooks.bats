#!/usr/bin/env bats

# Tests for the gitleaks commit scan: bin/git_hook_gitleaks.sh (a config-based
# git hook), bin/claude_commit_secret_scan.sh (the Claude Code fallback for
# older Git) and bin/install_claude_secret_scan_hook.sh.
#
# What these pin down: a staged secret stops the commit, and the repo's own
# setup wins — its installed gitleaks hook, its .gitleaks.toml.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  . "$REPO_ROOT/bin/git_fixture_helpers.sh"
  isolate_git_env
  GIT_HOOK="$REPO_ROOT/bin/git_hook_gitleaks.sh"
  COMMIT_SCAN="$REPO_ROOT/bin/claude_commit_secret_scan.sh"
  INSTALLER="$REPO_ROOT/bin/install_claude_secret_scan_hook.sh"
  TMP="$(mktemp -d)"
  export HOME="$TMP/home"
  mkdir -p "$HOME"
  SETTINGS="$HOME/.claude/settings.json"
  # Assembled at runtime so no scanner flags this file itself.
  TOKEN="ghp_$(printf 'a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6q7R8')"
}

teardown() {
  rm -rf "$TMP"
}

# A throwaway repo with one commit.
mkrepo() {
  REPO="$TMP/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
}

# commit_scan <command> [cwd]: run the commit scan on one Bash call.
commit_scan() {
  local payload
  payload=$(jq -nc --arg c "$1" --arg d "${2:-$REPO}" '{tool_input: {command: $c}, cwd: $d}')
  run bash -c 'printf "%s" "$1" | "$2"' _ "$payload" "$COMMIT_SCAN"
}

@test "git hook: a staged secret refuses the commit" {
  command -v gitleaks >/dev/null || skip "gitleaks not installed"
  mkrepo
  printf 'token = "%s"\n' "$TOKEN" >"$REPO/creds.txt"
  git -C "$REPO" add creds.txt
  run bash -c 'cd "$1" && "$2"' _ "$REPO" "$GIT_HOOK"
  [ "$status" -eq 1 ]
  [[ "$output" == *github-pat* ]]
  [[ "$output" != *"$TOKEN"* ]]
}

@test "git hook: a clean staged change passes" {
  command -v gitleaks >/dev/null || skip "gitleaks not installed"
  mkrepo
  printf 'hello\n' >"$REPO/a.txt"
  git -C "$REPO" add a.txt
  run bash -c 'cd "$1" && "$2"' _ "$REPO" "$GIT_HOOK"
  [ "$status" -eq 0 ]
}

@test "git hook: an unstaged secret is not this commit's" {
  command -v gitleaks >/dev/null || skip "gitleaks not installed"
  mkrepo
  printf 'token = "%s"\n' "$TOKEN" >"$REPO/creds.txt"
  run bash -c 'cd "$1" && "$2"' _ "$REPO" "$GIT_HOOK"
  [ "$status" -eq 0 ]
}

@test "git hook: stands down when the repo's installed hook runs gitleaks" {
  command -v gitleaks >/dev/null || skip "gitleaks not installed"
  mkrepo
  printf 'token = "%s"\n' "$TOKEN" >"$REPO/creds.txt"
  git -C "$REPO" add creds.txt
  printf '#!/bin/sh\ngitleaks git --staged\n' >"$REPO/.git/hooks/pre-commit"
  chmod +x "$REPO/.git/hooks/pre-commit"
  run "$GIT_HOOK" --repo-owns "$REPO"
  [ "$status" -eq 0 ]
  run bash -c 'cd "$1" && "$2"' _ "$REPO" "$GIT_HOOK"
  [ "$status" -eq 0 ]
}

@test "git hook: the repo's .gitleaks.toml decides what counts" {
  command -v gitleaks >/dev/null || skip "gitleaks not installed"
  mkrepo
  printf 'token = "%s"\n' "$TOKEN" >"$REPO/creds.txt"
  printf '[extend]\nuseDefault = true\n[[allowlists]]\nregexes = ["%s"]\n' "$TOKEN" >"$REPO/.gitleaks.toml"
  git -C "$REPO" add creds.txt
  run bash -c 'cd "$1" && "$2"' _ "$REPO" "$GIT_HOOK"
  [ "$status" -eq 0 ]
}

@test "git hook: the .gitconfig entry runs it, guarded for a missing ~/bin" {
  cmd=$(git config -f "$REPO_ROOT/.gitconfig" hook.dotfiles-gitleaks.command)
  [[ "$cmd" == *git_hook_gitleaks.sh* ]]
  [ "$(git config -f "$REPO_ROOT/.gitconfig" hook.dotfiles-gitleaks.event)" = pre-commit ]
  run sh -c "$cmd"
  [ "$status" -eq 0 ]
}

@test "commit: a command that is not a commit is ignored" {
  command -v gitleaks >/dev/null || skip "gitleaks not installed"
  mkrepo
  printf 'token = "%s"\n' "$TOKEN" >"$REPO/creds.txt"
  commit_scan 'git status'
  [ "$status" -eq 0 ]
  commit_scan 'echo "git commit"'
  [ "$status" -eq 0 ]
}

@test "commit: a clean change passes" {
  command -v gitleaks >/dev/null || skip "gitleaks not installed"
  mkrepo
  printf 'hello\n' >"$REPO/a.txt"
  commit_scan 'git add a.txt && git commit -m add'
  [ "$status" -eq 0 ]
}

@test "commit: a secret in a file not yet staged blocks add-and-commit" {
  command -v gitleaks >/dev/null || skip "gitleaks not installed"
  mkrepo
  printf 'token = "%s"\n' "$TOKEN" >"$REPO/creds.txt"
  commit_scan 'git add creds.txt && git commit -m add'
  [ "$status" -eq 2 ]
  [[ "$output" == *github-pat* ]]
  [[ "$output" != *"$TOKEN"* ]]
}

@test "commit: git -C points the scan at that repo" {
  command -v gitleaks >/dev/null || skip "gitleaks not installed"
  mkrepo
  printf 'token = "%s"\n' "$TOKEN" >"$REPO/creds.txt"
  commit_scan "git -C $REPO commit -am add" "$TMP"
  [ "$status" -eq 2 ]
}

@test "commit: the repo's installed gitleaks hook takes precedence" {
  command -v gitleaks >/dev/null || skip "gitleaks not installed"
  mkrepo
  printf 'token = "%s"\n' "$TOKEN" >"$REPO/creds.txt"
  printf '#!/bin/sh\ngitleaks git --staged\n' >"$REPO/.git/hooks/pre-commit"
  chmod +x "$REPO/.git/hooks/pre-commit"
  commit_scan 'git add creds.txt && git commit -m add'
  [ "$status" -eq 0 ]
  # ...unless the commit skips the repo's hooks.
  commit_scan 'git add creds.txt && git commit --no-verify -m add'
  [ "$status" -eq 2 ]
}

@test "commit: a config naming gitleaks without an installed hook does not count" {
  command -v gitleaks >/dev/null || skip "gitleaks not installed"
  mkrepo
  printf 'token = "%s"\n' "$TOKEN" >"$REPO/creds.txt"
  printf 'pre-commit:\n  commands:\n    gitleaks:\n      run: gitleaks git --staged\n' >"$REPO/lefthook.yml"
  commit_scan 'git add creds.txt && git commit -m add'
  [ "$status" -eq 2 ]
}

@test "commit: the repo's .gitleaks.toml decides what counts" {
  command -v gitleaks >/dev/null || skip "gitleaks not installed"
  mkrepo
  printf 'token = "%s"\n' "$TOKEN" >"$REPO/creds.txt"
  printf '[extend]\nuseDefault = true\n[[allowlists]]\nregexes = ["%s"]\n' "$TOKEN" >"$REPO/.gitleaks.toml"
  commit_scan 'git add creds.txt && git commit -m add'
  [ "$status" -eq 0 ]
}

@test "commit: outside a repo it fails open" {
  command -v gitleaks >/dev/null || skip "gitleaks not installed"
  mkdir -p "$TMP/plain"
  commit_scan 'git commit -m x' "$TMP/plain"
  [ "$status" -eq 0 ]
}

# fake_git_version <x.y.z>: put a git on PATH that reports that version and
# otherwise runs the real one, so both sides of the 2.54 cut run anywhere.
fake_git_version() {
  local real_git
  real_git=$(command -v git)
  mkdir -p "$TMP/shim-$1"
  printf '#!/bin/sh\n[ "$1" = --version ] && { echo "git version %s"; exit 0; }\nexec %s "$@"\n' \
    "$1" "$real_git" >"$TMP/shim-$1/git"
  chmod +x "$TMP/shim-$1/git"
  echo "$TMP/shim-$1"
}

@test "commit: defers to git's own hook on Git 2.54+" {
  command -v gitleaks >/dev/null || skip "gitleaks not installed"
  mkrepo
  printf 'token = "%s"\n' "$TOKEN" >"$REPO/creds.txt"
  git -C "$REPO" config hook.dotfiles-gitleaks.event pre-commit
  git -C "$REPO" config hook.dotfiles-gitleaks.command "$GIT_HOOK"
  # Older Git would not run the config hook, so this one scans.
  PATH="$(fake_git_version 2.43.0):$PATH" commit_scan 'git add creds.txt && git commit -m add'
  [ "$status" -eq 2 ]
  PATH="$(fake_git_version 2.54.0):$PATH" commit_scan 'git add creds.txt && git commit -m add'
  [ "$status" -eq 0 ]
}

@test "git 2.54+ runs the config hook and refuses the commit" {
  command -v gitleaks >/dev/null || skip "gitleaks not installed"
  mkrepo
  # Same version test as the fallback, so the two cannot disagree.
  v=$(git --version | sed -nE 's/^git version ([0-9]+)\.([0-9]+).*/\1 \2/p')
  read -r maj min <<<"$v"
  { [ "$maj" -gt 2 ] || { [ "$maj" -eq 2 ] && [ "$min" -ge 54 ]; }; } || skip "git $maj.$min has no config hooks"
  git -C "$REPO" config hook.dotfiles-gitleaks.event pre-commit
  git -C "$REPO" config hook.dotfiles-gitleaks.command "$GIT_HOOK"
  printf 'token = "%s"\n' "$TOKEN" >"$REPO/creds.txt"
  git -C "$REPO" add creds.txt
  run git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -q -m add
  [ "$status" -ne 0 ]
  [[ "$output" == *github-pat* ]]
  run git -C "$REPO" rev-list --count HEAD
  [ "$output" = 1 ]
}

@test "install: registers the hook once, keeps other settings, and uninstalls" {
  mkdir -p "$HOME/.claude"
  printf '{"theme":"dark","hooks":{"Stop":[{"hooks":[{"type":"command","command":"x"}]}]}}\n' >"$SETTINGS"
  run "$INSTALLER"
  [ "$status" -eq 0 ]
  run "$INSTALLER"
  [ "$status" -eq 0 ]
  n=$(jq '[.hooks.PreToolUse[].hooks[].command | select(contains("claude_commit_secret_scan.sh"))] | length' \
    "$SETTINGS")
  [ "$n" -eq 1 ]
  jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash")' "$SETTINGS" >/dev/null
  jq -e '.theme == "dark" and (.hooks.Stop | length == 1)' "$SETTINGS" >/dev/null
  run "$INSTALLER" --uninstall
  [ "$status" -eq 0 ]
  jq -e '.hooks.PreToolUse == null and .theme == "dark" and (.hooks.Stop | length == 1)' "$SETTINGS" >/dev/null
}

@test "cloud settings register the same handler" {
  cloud="$REPO_ROOT/claudecode/settings-cloud.json"
  jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash")
    | .hooks[].command | contains("claude_commit_secret_scan.sh")' "$cloud" >/dev/null
}
