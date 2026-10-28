#!/usr/bin/env bats

# Every language server nvim enables must come from Brewfile.extra, which marks
# it with "(nvim LSP: <name>)" — the promise at the top of plugins/lsp.lua that
# nothing is downloaded when nvim starts. A server enabled without a formula
# only warns once in the editor, so nothing else would notice.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  LSP_LUA="$REPO_ROOT/config/nvim/lua/kimoto/plugins/lsp.lua"
}

enabled_servers() {
  awk '/^local servers = \{/ { on = 1; next } on && /^\}/ { exit }
       on { if (match($0, /'"'"'[a-z_]+'"'"'/)) print substr($0, RSTART + 1, RLENGTH - 2) }' "$LSP_LUA"
}

@test "the server list in plugins/lsp.lua parses" {
  run enabled_servers
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -ge 5 ]
}

@test "every enabled server has a Brewfile.extra formula" {
  missing=()
  for server in $(enabled_servers); do
    # sqls has no Homebrew formula; lsp.lua says to install it with Mason.
    [ "$server" = sqls ] && continue
    grep -Eq "\(nvim LSP: ([a-z_]+, )*$server(,|\))" "$REPO_ROOT/Brewfile.extra" || missing+=("$server")
  done
  [ "${#missing[@]}" -eq 0 ] || { echo "no Brewfile.extra entry for: ${missing[*]}"; return 1; }
}
