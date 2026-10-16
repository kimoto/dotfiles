#!/usr/bin/env bats

# Every binding .tmux.conf makes carries a note (-N), so `tmux list-keys -N`
# and which-key's Keys menu describe this setup's keys rather than only
# tmux's defaults. A binding without one is silently missing from both lists.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "every bind-key in .tmux.conf has a note" {
  local missing
  missing="$(grep -nE '(^|[^-[:alnum:]])bind-key ' "$REPO_ROOT/.tmux.conf" |
    grep -vE '^[0-9]+:[[:space:]]*#' |
    grep -v 'bind-key -N ' || true)"
  if [ -n "$missing" ]; then
    echo "bind-key without -N:" >&2
    echo "$missing" >&2
    return 1
  fi
}

@test "the notes reach tmux's own key list" {
  local sock="binding_notes_$$" listed
  tmux -L "$sock" -f "$REPO_ROOT/.tmux.conf" new-session -d -s NOTES
  listed="$(tmux -L "$sock" list-keys -N)"
  tmux -L "$sock" kill-server
  [[ "$listed" == *"hunk: live diff of this checkout beside the pane"* ]]
}
