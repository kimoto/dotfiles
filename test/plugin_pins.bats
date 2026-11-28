#!/usr/bin/env bats

# Every zsh and tmux plugin must name the commit it is checked out at.
# Without a pin, sheldon and tpm clone whatever the branch head is at install
# time, so a plugin added in a hurry would skip the Renovate age gate.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "every github plugin in sheldon's plugins.toml has a rev on the next line" {
  run awk '
    /^github = / { want = $3; next }
    want != "" { if ($0 !~ /^rev = '\''[0-9a-f]{40}'\'' # [^ ]+$/) print want; want = "" }
    END { if (want != "") print want }
  ' "$REPO_ROOT/config/sheldon/plugins.toml"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "unpinned: $output"; false; }
}

@test "every @tpm_plugins entry has a commit in tmux-plugins.lock, and nothing else does" {
  declared=$(sed -n "/^set -g @tpm_plugins '/,/^'/p" "$REPO_ROOT/.tmux.conf" \
    | grep -oE '[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' | sort)
  locked=$(awk '!/^#/ && NF == 3 && $3 ~ /^[0-9a-f]{40}$/ { print $1 }' \
    "$REPO_ROOT/tmux-plugins.lock" | sort)
  [ -n "$declared" ]
  [ "$declared" = "$locked" ] || { diff <(echo "$declared") <(echo "$locked"); false; }
}
