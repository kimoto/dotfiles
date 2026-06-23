#!/usr/bin/env bats

# Tests for bin/lint_schema.sh, which validates config files against the JSON
# Schema they declare via a top-level "$schema" key.
#
# Everything runs OFFLINE: fixtures point "$schema" at a local schema file on
# disk, so check-jsonschema never reaches the network. The script cd's into the
# real repo root, so fixtures are passed as ABSOLUTE paths. The most valuable
# cases here exercise the hand-rolled JSONC comment/trailing-comma stripper:
# comments and trailing commas must be removed, but comment-like markers inside
# string values must be preserved.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/lint_schema.sh"
  TMP="$(mktemp -d)"

  # A small permissive schema: requires a string "name", and tolerates the
  # "$schema" key itself (no additionalProperties:false).
  SCHEMA="$TMP/schema.json"
  cat >"$SCHEMA" <<'EOF'
{
  "type": "object",
  "properties": { "name": { "type": "string" } },
  "required": ["name"]
}
EOF
}

teardown() {
  rm -rf "$TMP"
}

@test "valid JSON passes its declared schema" {
  cat >"$TMP/good.json" <<EOF
{ "\$schema": "$SCHEMA", "name": "ok" }
EOF
  run "$SCRIPT" "$TMP/good.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok $TMP/good.json"* ]]
}

@test "invalid JSON fails its declared schema" {
  cat >"$TMP/bad.json" <<EOF
{ "\$schema": "$SCHEMA", "name": 123 }
EOF
  run "$SCRIPT" "$TMP/bad.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"schema validation failed"* ]]
}

@test "a file without a \$schema key is skipped silently" {
  echo '{ "name": "whatever" }' >"$TMP/noschema.json"
  run "$SCRIPT" "$TMP/noschema.json"
  [ "$status" -eq 0 ]
  [[ "$output" != *"ok "* ]]
}

@test "validates TOML via its \$schema" {
  cat >"$TMP/cfg.toml" <<EOF
"\$schema" = "$SCHEMA"
name = "ok"
EOF
  run "$SCRIPT" "$TMP/cfg.toml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok $TMP/cfg.toml"* ]]
}

@test "validates YAML via its \$schema" {
  cat >"$TMP/cfg.yaml" <<EOF
"\$schema": "$SCHEMA"
name: ok
EOF
  run "$SCRIPT" "$TMP/cfg.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok $TMP/cfg.yaml"* ]]
}

@test "JSONC: comments and a trailing comma are stripped before validation" {
  cat >"$TMP/cfg.jsonc" <<EOF
{
  // a line comment that must be removed
  "\$schema": "$SCHEMA",
  /* a block comment
     spanning multiple lines */
  "name": "ok",
}
EOF
  run "$SCRIPT" "$TMP/cfg.jsonc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok $TMP/cfg.jsonc"* ]]
}

@test "JSONC: comment-like markers inside a string are NOT stripped" {
  # The schema pins name to a value containing // and /* */, so the run only
  # passes if the stripper left the string contents untouched.
  cat >"$TMP/strschema.json" <<'EOF'
{
  "type": "object",
  "properties": { "name": { "const": "a // b /* c */" } },
  "required": ["name"]
}
EOF
  cat >"$TMP/str.jsonc" <<EOF
{
  // real comment, stripped
  "\$schema": "$TMP/strschema.json",
  "name": "a // b /* c */",
}
EOF
  run "$SCRIPT" "$TMP/str.jsonc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok $TMP/str.jsonc"* ]]
}

@test "schema hosts in SKIP_HOSTS are skipped without a network call" {
  printf '"$schema" = "https://starship.rs/config-schema.json"\n' >"$TMP/starship.toml"
  run "$SCRIPT" "$TMP/starship.toml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip"* ]]
  [[ "$output" == *"starship.rs"* ]]
}

@test "a mixed batch fails if any single file is invalid" {
  cat >"$TMP/ok.json" <<EOF
{ "\$schema": "$SCHEMA", "name": "ok" }
EOF
  cat >"$TMP/nope.json" <<EOF
{ "\$schema": "$SCHEMA", "name": 123 }
EOF
  run "$SCRIPT" "$TMP/ok.json" "$TMP/nope.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ok $TMP/ok.json"* ]]
  [[ "$output" == *"schema validation failed: $TMP/nope.json"* ]]
}
