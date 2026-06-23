#!/usr/bin/env bats

# Tests for bin/lint_schema.sh — the JSON Schema guard for config files that
# declare a top-level "$schema".
#
# Everything is wired to a LOCAL schema file (fixtures point their "$schema" at
# an absolute temp path), so the suite validates the script's real behaviour
# without touching the network or depending on any remote schema host.
#
# Coverage: a valid file passes, a schema-violating file fails (proves the
# check actually validates and isn't a no-op), JSONC comments + trailing commas
# are handled (the comment-stripping path), plain .json is validated too, files
# without a "$schema" are skipped, and a SKIP_HOSTS host is skipped not fetched.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/lint_schema.sh"
  TMP="$(mktemp -d)"

  # Minimal local schema: requires a top-level "modules" array.
  cat >"$TMP/schema.json" <<'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["modules"],
  "properties": { "modules": { "type": "array" } }
}
EOF
}

teardown() {
  rm -rf "$TMP"
}

@test "passes a valid .jsonc with comments and a trailing comma" {
  cat >"$TMP/good.jsonc" <<EOF
{
  // a comment, plus a trailing comma below — both only legal in JSONC/JSON5
  "\$schema": "$TMP/schema.json",
  "modules": ["host", "os",]
}
EOF
  run "$SCRIPT" "$TMP/good.jsonc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "fails a .jsonc that violates the schema" {
  cat >"$TMP/bad.jsonc" <<EOF
{
  "\$schema": "$TMP/schema.json",
  "modules": 123
}
EOF
  run "$SCRIPT" "$TMP/bad.jsonc"
  [ "$status" -eq 1 ]
  [[ "$output" == *"schema validation failed"* ]]
}

@test "validates plain .json too" {
  cat >"$TMP/good.json" <<EOF
{ "\$schema": "$TMP/schema.json", "modules": ["x"] }
EOF
  run "$SCRIPT" "$TMP/good.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]

  cat >"$TMP/bad.json" <<EOF
{ "\$schema": "$TMP/schema.json", "modules": "not-an-array" }
EOF
  run "$SCRIPT" "$TMP/bad.json"
  [ "$status" -eq 1 ]
}

@test "skips a file that declares no \$schema" {
  # Schema-violating content, but with no "$schema" key it must be left alone.
  cat >"$TMP/noschema.jsonc" <<'EOF'
{ "modules": 123 }
EOF
  run "$SCRIPT" "$TMP/noschema.jsonc"
  [ "$status" -eq 0 ]
  [[ "$output" != *"failed"* ]]
}

@test "skips (does not fetch) a schema on a SKIP_HOSTS host" {
  cat >"$TMP/starship.jsonc" <<'EOF'
{
  "$schema": "https://starship.rs/config-schema.json",
  "modules": 123
}
EOF
  run "$SCRIPT" "$TMP/starship.jsonc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip"* ]]
  [[ "$output" == *"starship.rs"* ]]
}
