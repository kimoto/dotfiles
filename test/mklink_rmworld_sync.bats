#!/usr/bin/env bats

# Guards the invariant both scripts document in their own comments:
# bin/rmworld.sh must unlink exactly the set of $HOME entries that
# bin/mklink.sh links. If someone adds/removes a link in one script but
# forgets the other, mkworld/rmworld stop being inverses and stale symlinks
# get left behind (or real files get clobbered). This test fails loudly the
# moment the two lists drift apart.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  MKLINK="$REPO_ROOT/bin/mklink.sh"
  RMWORLD="$REPO_ROOT/bin/rmworld.sh"
}

# The $HOME entry names mklink.sh creates. Each `ln` line is either
#   ln ... "$BASE_DIR/<src>" ./<name>   -> link name is <name>
#   ln ... "$BASE_DIR/<src>" ./         -> link name is basename(<src>)
# (e.g. `... "$BASE_DIR/config" ./.config` links .config, not config), so the
# destination wins when it is named and the source basename is used otherwise.
mklink_targets() {
  awk '/ln -/ {
    s = $0
    sub(/^[^"]*"/, "", s); src = s; sub(/".*/, "", src)   # src = $BASE_DIR/...
    dest = $NF
    if (dest == "./") { sub(/\/$/, "", src); sub(/.*\//, "", src); print src }
    else { sub(/^\.\//, "", dest); sub(/\/$/, "", dest); print dest }
  }' "$MKLINK" | sort -u
}

# Entries rmworld.sh unlinks: the argument of each unlink_if_symlink call,
# leading "./" stripped, trailing slash normalised.
rmworld_targets() {
  grep -oE 'unlink_if_symlink "\./[^"]*"' "$RMWORLD" \
    | sed -E 's/.*"\.\/([^"]*)"/\1/' \
    | sed -E 's#/$##' \
    | sort -u
}

@test "every file mklink.sh links is unlinked by rmworld.sh" {
  diff <(mklink_targets) <(rmworld_targets)
}

@test "mklink.sh actually links something (guards against a broken parser)" {
  run mklink_targets
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}
