#!/usr/bin/env bats

# Tests for bin/fzf_preview.sh, the Ctrl-T preview in .zshrc.
#
# What these pin down: images reach chafa sized to the preview pane, everything
# else still reaches bat, and a machine without chafa still gets a preview.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/bin"
  # Stand-ins that print how they were called, so the real tools, installed or
  # not, stay out of reach.
  for t in bat chafa; do
    printf '#!/bin/sh\necho "%s $*"\n' "$t" >"$TMP/bin/$t"
    chmod +x "$TMP/bin/$t"
  done
  ln -s "$(command -v sh)" "$TMP/bin/sh"
}

teardown() {
  rm -rf "$TMP"
}

preview() {
  run env PATH="$TMP/bin" FZF_PREVIEW_COLUMNS=40 FZF_PREVIEW_LINES=10 \
    "$TMP/bin/sh" "$REPO_ROOT/bin/fzf_preview.sh" "$1"
}

@test "an image is drawn by chafa at the preview pane's size" {
  preview photo.png
  [ "$status" -eq 0 ]
  [ "$output" = "chafa --format symbols --animate off --size 40x10 photo.png" ]
}

@test "an upper-case image extension still reaches chafa" {
  preview IMG_0001.JPG
  [[ "$output" == "chafa "* ]]
}

@test "a text file goes to bat" {
  preview notes.md
  [ "$output" = "bat --color=always notes.md" ]
}

@test "without chafa an image falls back to bat" {
  rm "$TMP/bin/chafa"
  preview photo.png
  [ "$status" -eq 0 ]
  [ "$output" = "bat --color=always photo.png" ]
}
