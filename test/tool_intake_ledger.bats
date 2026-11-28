#!/usr/bin/env bats

# tool-intake's rejected tools live in the one decision ledger
# (docs/scouts.md), not in a second table inside the skill, so the two cannot
# drift apart.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SKILL="$REPO_ROOT/claudecode/skills/tool-intake/SKILL.md"
  LEDGER="$REPO_ROOT/docs/scouts.md"
}

@test "the ledger has a section for rejected tools" {
  grep -qx '## Decided against: tools' "$LEDGER"
}

@test "tool-intake keeps no table of its own and reads the ledger" {
  run grep -n '^|' "$SKILL"
  [ "$status" -ne 0 ]
  grep -q 'Decided against: tools' "$SKILL"
}
