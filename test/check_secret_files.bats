#!/usr/bin/env bats

# Tests for bin/check_secret_files.sh.
#
# The script must REJECT sensitive filenames (private keys, key/cert
# extensions, .env files) and ACCEPT ordinary files and the documented
# .env.{example,sample,template,dist} exceptions. Names are passed as
# arguments, so these are pure name checks: no real files need to exist.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/check_secret_files.sh"
}

@test "accepts ordinary files" {
  run "$SCRIPT" README.md config/starship.toml .zshrc
  [ "$status" -eq 0 ]
}

@test "rejects an SSH private key by basename" {
  run "$SCRIPT" id_rsa
  [ "$status" -eq 1 ]
  [[ "$output" == *"Sensitive files detected"* ]]
}

@test "rejects id_ed25519 in a subdirectory" {
  run "$SCRIPT" some/nested/path/id_ed25519
  [ "$status" -eq 1 ]
}

@test "rejects sensitive extensions" {
  for f in cert.pem private.key bundle.p12 vault.kdbx server.pfx store.jks; do
    run "$SCRIPT" "$f"
    [ "$status" -eq 1 ]
  done
}

@test "rejects a bare .env file" {
  run "$SCRIPT" .env
  [ "$status" -eq 1 ]
}

@test "rejects an environment-specific .env.local file" {
  run "$SCRIPT" .env.local
  [ "$status" -eq 1 ]
}

@test "allows example/sample/template/dist env files" {
  run "$SCRIPT" .env.example .env.sample config/.env.template .env.dist
  [ "$status" -eq 0 ]
}

@test "rejects the whole set if even one file is sensitive" {
  run "$SCRIPT" README.md id_rsa notes.txt
  [ "$status" -eq 1 ]
}
