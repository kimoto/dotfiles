#!/usr/bin/env bats

# Tests for bin/lint_config.sh, which validates the *syntax* (not schema) of
# structured config files. The script routes by extension:
#   .json/.toml/.yaml/.yml -> yq -p <parser>
#   .jsonc                  -> biome lint (yq has no JSONC mode)
#   mise.toml               -> also `mise lock --check`, so mise must be on PATH
# Fixtures are passed as explicit arguments, so the git-ls-files default path is
# not exercised here (the no-args case proves the repo's own files are valid).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/lint_config.sh"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

@test "accepts valid JSON" {
  printf '{ "a": 1, "b": ["x", "y"] }\n' >"$TMP/good.json"
  run "$SCRIPT" "$TMP/good.json"
  [ "$status" -eq 0 ]
}

@test "rejects malformed JSON" {
  printf '{ "a": 1, \n' >"$TMP/bad.json"   # unterminated object
  run "$SCRIPT" "$TMP/bad.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid json syntax: $TMP/bad.json"* ]]
}

@test "accepts valid TOML" {
  printf 'a = 1\nb = "x"\n' >"$TMP/good.toml"
  run "$SCRIPT" "$TMP/good.toml"
  [ "$status" -eq 0 ]
}

@test "rejects malformed TOML" {
  printf 'a = = 1\n' >"$TMP/bad.toml"
  run "$SCRIPT" "$TMP/bad.toml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid toml syntax: $TMP/bad.toml"* ]]
}

@test "accepts valid YAML (both .yaml and .yml route to the yaml parser)" {
  printf 'a: 1\nb:\n  - x\n  - y\n' >"$TMP/good.yaml"
  printf 'a: 1\n' >"$TMP/good.yml"
  run "$SCRIPT" "$TMP/good.yaml" "$TMP/good.yml"
  [ "$status" -eq 0 ]
}

@test "rejects malformed YAML" {
  printf 'a: 1\n  b: 2\n' >"$TMP/bad.yaml"   # bad indentation / mapping
  run "$SCRIPT" "$TMP/bad.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid yaml syntax: $TMP/bad.yaml"* ]]
}

@test "accepts valid JSONC (comments + trailing commas) via biome" {
  cat >"$TMP/good.jsonc" <<'EOF'
{
  // a line comment
  "a": 1,
  /* block comment */
  "b": [1, 2,],
}
EOF
  run "$SCRIPT" "$TMP/good.jsonc"
  [ "$status" -eq 0 ]
}

@test "rejects malformed JSONC via biome" {
  printf '{ "a": 1 \n' >"$TMP/bad.jsonc"   # unterminated object
  run "$SCRIPT" "$TMP/bad.jsonc"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid jsonc syntax"* ]]
}

@test "fails a mixed batch if any single file is invalid" {
  printf '{ "a": 1 }\n' >"$TMP/ok.json"
  printf 'a = = 1\n' >"$TMP/bad.toml"
  run "$SCRIPT" "$TMP/ok.json" "$TMP/bad.toml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid toml syntax: $TMP/bad.toml"* ]]
}

@test "no arguments and a clean repo exits 0 (repo's own config files are valid)" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}

# mise.lock next to a linted mise.toml must match it, or `mise install --locked`
# stops (for a missing uv project directory, with no hint that `mise lock` was
# skipped). The fixture is the repo's own lockfile, so it starts out valid.
mise_lock_fixture() {
  cp "$REPO_ROOT/mise.toml" "$REPO_ROOT/mise.lock" "$TMP/"
  cp -R "$REPO_ROOT/.mise" "$TMP/.mise"
}

@test "accepts a mise.lock that matches its mise.toml" {
  mise_lock_fixture
  run "$SCRIPT" "$TMP/mise.toml"
  [ "$status" -eq 0 ]
}

@test "rejects a mise.lock whose uv project directory is missing" {
  mise_lock_fixture
  rm -rf "$TMP/.mise/locks"
  run "$SCRIPT" "$TMP/mise.toml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"mise lock --check rejected $TMP/mise.lock"* ]]
}

@test "rejects a version bumped in mise.toml without mise lock" {
  mise_lock_fixture
  # The first inline-table pin (`version = "..."`), whatever it is today,
  # moved to a version never locked.
  awk '!done && sub(/version = "[^"]+"/, "version = \"0.0.1\"") { done = 1 } { print }' \
    "$REPO_ROOT/mise.toml" >"$TMP/mise.toml"
  run cmp -s "$REPO_ROOT/mise.toml" "$TMP/mise.toml"
  [ "$status" -ne 0 ]  # the awk found a pin to bump
  run "$SCRIPT" "$TMP/mise.toml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"mise lock --check rejected $TMP/mise.lock"* ]]
}

@test "an untrusted mise.toml above the checkout is not read" {
  mkdir "$TMP/inner"
  cp "$REPO_ROOT/mise.toml" "$REPO_ROOT/mise.lock" "$TMP/inner/"
  cp -R "$REPO_ROOT/.mise" "$TMP/inner/.mise"
  # An [env] table is what makes mise demand trust before reading a file.
  printf '[env]\nFOO = "bar"\n' >"$TMP/mise.toml"
  run "$SCRIPT" "$TMP/inner/mise.toml"
  [ "$status" -eq 0 ]
}
