#!/usr/bin/env bats

# Tests for hammerspoon/translate.py — what it sends to the API, against a
# stub SDK, since the real call needs a key and the Mac's clipboard and dialog
# tools. What must hold: the target language follows the text (Japanese →
# English, anything else → Japanese) unless --to fixes it, an image goes as
# a base64 block, and the key comes from the Keychain only — never from the
# environment, where every child process would see it.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/hammerspoon/translate.py"
  TMP="$(mktemp -d)"
  export REQUEST="$TMP/request.json"

  # The SDK: record the stream() call, answer with a fixed translation that
  # arrives in two pieces.
  mkdir -p "$TMP/py"
  cat >"$TMP/py/anthropic.py" <<'EOF'
import json, os
class APIStatusError(Exception): pass
class AuthenticationError(APIStatusError): pass
class RateLimitError(APIStatusError): pass
class APIConnectionError(Exception): pass
class _Obj:
    def __init__(self, **kw): self.__dict__.update(kw)
class _Stream:
    text_stream = ["TRANS", "LATED"]
    def __enter__(self): return self
    def __exit__(self, *exc): return False
    def get_final_message(self):
        return _Obj(stop_reason="end_turn", content=[_Obj(type="text", text="TRANSLATED")])
class _Messages:
    def stream(self, **kw):
        with open(os.environ["REQUEST"], "w") as f:
            json.dump(kw, f)
        return _Stream()
class Anthropic:
    def __init__(self, api_key):
        with open(os.environ["REQUEST"] + ".key", "w") as f:
            f.write(api_key)
        self.beta = _Obj(messages=_Messages())
EOF

  # The macOS tools it shells out to. `security` answers only when the test
  # puts a key in the stub Keychain.
  mkdir -p "$TMP/bin"
  printf '#!/bin/sh\n[ -n "$STUB_KEYCHAIN" ] || exit 44\necho "$STUB_KEYCHAIN"\n' >"$TMP/bin/security"
  printf '#!/bin/sh\necho clipboard text\n' >"$TMP/bin/pbpaste"
  printf '#!/bin/sh\ncat >/dev/null\n' >"$TMP/bin/pbcopy"
  printf '#!/bin/sh\nexit 0\n' >"$TMP/bin/osascript"
  chmod +x "$TMP/bin/"*

  export PATH="$TMP/bin:$PATH" PYTHONPATH="$TMP/py" STUB_KEYCHAIN=sk-from-keychain
}

teardown() {
  rm -rf "$TMP"
}

# Prints one block of the recorded user message: its text, or the image's
# media type.
request_block() {
  python3 - "$REQUEST" "$1" <<'PY'
import json, sys
for block in json.load(open(sys.argv[1]))["messages"][0]["content"]:
    if block["type"] == sys.argv[2]:
        print(block["text"] if block["type"] == "text" else block["source"]["media_type"])
PY
}

request_text() {
  request_block text
}

@test "English text is sent to be translated into Japanese" {
  run python3 "$SCRIPT" --quiet "The quick brown fox"
  [ "$status" -eq 0 ]
  [ "$output" = "TRANSLATED" ]
  [[ "$(request_text)" == "Translate the following into Japanese."* ]]
}

@test "Japanese text is sent to be translated into English, despite English names in it" {
  run python3 "$SCRIPT" --quiet "今日は Claude Code と Hammerspoon を設定した"
  [ "$status" -eq 0 ]
  [[ "$(request_text)" == "Translate the following into English."* ]]
}

@test "--to fixes the target language" {
  run python3 "$SCRIPT" --quiet --to en "The quick brown fox"
  [ "$status" -eq 0 ]
  [[ "$(request_text)" == "Translate the following into English."* ]]
}

@test "--clipboard reads the clipboard, not stdin" {
  run bash -c 'echo "from stdin" | python3 "$0" --quiet --clipboard' "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$(request_text)" == *"clipboard text"* ]]
  [[ "$(request_text)" != *"from stdin"* ]]
}

@test "an image goes as a base64 block and leaves the language to the model" {
  printf '\x89PNG fake' >"$TMP/shot.png"
  run python3 "$SCRIPT" --quiet --image "$TMP/shot.png"
  [ "$status" -eq 0 ]
  [ "$(request_block image)" = "image/png" ]
  [[ "$(request_text)" == *"If it is mostly Japanese"* ]]
}

@test "the key comes from the Keychain" {
  run python3 "$SCRIPT" --quiet "hello"
  [ "$status" -eq 0 ]
  [ "$(cat "$REQUEST.key")" = "sk-from-keychain" ]
}

@test "no key in the Keychain fails, even with keys in the environment" {
  STUB_KEYCHAIN=""
  export ANTHROPIC_API_KEY=x DESKTOP_TRANSLATE_API_KEY=x
  run python3 "$SCRIPT" --quiet "hello"
  [ "$status" -eq 1 ]
  [ ! -e "$REQUEST.key" ]
}
