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
    def __init__(self, api_key, base_url=None):
        with open(os.environ["REQUEST"] + ".key", "w") as f:
            f.write(api_key)
        with open(os.environ["REQUEST"] + ".base", "w") as f:
            f.write(str(base_url))
        self.beta = _Obj(messages=_Messages())
EOF

  # The OpenAI SDK the same way: the Responses API's streamed events.
  cat >"$TMP/py/openai.py" <<'EOF'
import json, os
class APIStatusError(Exception): pass
class AuthenticationError(APIStatusError): pass
class RateLimitError(APIStatusError): pass
class APIConnectionError(Exception): pass
class _Obj:
    def __init__(self, **kw): self.__dict__.update(kw)
class _Responses:
    def create(self, **kw):
        with open(os.environ["REQUEST"], "w") as f:
            json.dump(kw, f)
        events = [_Obj(type="response.created"),
                  _Obj(type="response.output_text.delta", delta="TRANS"),
                  _Obj(type="response.output_text.delta", delta="LATED")]
        if os.environ.get("STUB_REFUSAL"):
            events = [_Obj(type="response.refusal.delta", delta="No."),
                      _Obj(type="response.refusal.done", refusal="No."),
                      _Obj(type="response.completed")]
        if os.environ.get("STUB_INCOMPLETE"):
            details = _Obj(reason="max_output_tokens")
            events.append(_Obj(type="response.incomplete", response=_Obj(incomplete_details=details)))
        return iter(events)
class OpenAI:
    def __init__(self, api_key, base_url=None):
        with open(os.environ["REQUEST"] + ".key", "w") as f:
            f.write(api_key)
        with open(os.environ["REQUEST"] + ".base", "w") as f:
            f.write(str(base_url))
        self.responses = _Responses()
EOF

  # The macOS tools it shells out to. `security` answers only when the test
  # puts a key in the stub Keychain, and names the account (-a) it was asked
  # for in the key, so a test can see which entry was read.
  mkdir -p "$TMP/bin"
  cat >"$TMP/bin/security" <<'EOF'
#!/bin/sh
[ -n "$STUB_KEYCHAIN" ] || exit 44
account=none
while [ $# -gt 0 ]; do
  [ "$1" = "-a" ] && account="$2"
  shift
done
echo "$STUB_KEYCHAIN:$account"
EOF
  printf '#!/bin/sh\necho clipboard text\n' >"$TMP/bin/pbpaste"
  printf '#!/bin/sh\ncat >/dev/null\n' >"$TMP/bin/pbcopy"
  printf '#!/bin/sh\nexit 0\n' >"$TMP/bin/osascript"
  chmod +x "$TMP/bin/"*

  # HOME too: the config file and instructions are read from under it, and
  # the machine's own must not decide what these tests send. The interpreter
  # is pinned first, since a version manager's shim reads its state from HOME.
  ln -s "$(python3 -c 'import sys; print(sys.executable)')" "$TMP/bin/python3"
  mkdir -p "$TMP/home/.local/share/desktop-translate"
  CONFIG="$TMP/home/.local/share/desktop-translate/config.toml"
  export PATH="$TMP/bin:$PATH" PYTHONPATH="$TMP/py" STUB_KEYCHAIN=sk-from-keychain HOME="$TMP/home"
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
  [ "$(cat "$REQUEST.key")" = "sk-from-keychain:anthropic" ]
  [ "$(cat "$REQUEST.base")" = "None" ]
}

@test "no key in the Keychain fails, even with keys in the environment" {
  STUB_KEYCHAIN=""
  export ANTHROPIC_API_KEY=x DESKTOP_TRANSLATE_API_KEY=x
  run python3 "$SCRIPT" --quiet "hello"
  [ "$status" -eq 1 ]
  [ ! -e "$REQUEST.key" ]
}

@test "--screen and --image together are refused, and the image is left alone" {
  printf '\x89PNG fake' >"$TMP/mine.png"
  run python3 "$SCRIPT" --quiet --screen --image "$TMP/mine.png"
  [ "$status" -ne 0 ]
  [ -e "$TMP/mine.png" ]
}

# Prints one field of the recorded Responses API request.
openai_field() {
  python3 - "$REQUEST" "$1" <<'PY'
import json, sys
req = json.load(open(sys.argv[1]))
part = {p["type"]: p for p in req["input"][0]["content"]}
print({
    "model": req.get("model"),
    "text": part.get("input_text", {}).get("text"),
    "image": (part.get("input_image", {}).get("image_url") or "")[:22],
    "reasoning": req.get("reasoning"),
}[sys.argv[2]])
PY
}

@test "a custom endpoint in the config gets the request, with its own key" {
  printf 'provider = "openai"\nbase_url = "https://gw.example/v1"\nmodel = "some-model"\n' >"$CONFIG"
  run python3 "$SCRIPT" --quiet "The quick brown fox"
  [ "$status" -eq 0 ]
  [ "$output" = "TRANSLATED" ]
  [ "$(cat "$REQUEST.base")" = "https://gw.example/v1" ]
  [ "$(cat "$REQUEST.key")" = "sk-from-keychain:openai" ]
  [ "$(openai_field model)" = "some-model" ]
  [[ "$(openai_field text)" == "Translate the following into Japanese."* ]]
  [ "$(openai_field reasoning)" = "None" ]
}

@test "an image goes to a custom endpoint as a data URL" {
  printf 'provider = "openai"\nmodel = "some-model"\n' >"$CONFIG"
  printf '\x89PNG fake' >"$TMP/shot.png"
  run python3 "$SCRIPT" --quiet --image "$TMP/shot.png"
  [ "$status" -eq 0 ]
  [ "$(openai_field image)" = "data:image/png;base64," ]
}

@test "an answer cut short by a custom endpoint says so" {
  printf 'provider = "openai"\nmodel = "some-model"\n' >"$CONFIG"
  STUB_INCOMPLETE=1 run python3 "$SCRIPT" --quiet "hello"
  [ "$status" -eq 0 ]
  [[ "$output" == *"途中で切れました"* ]]
}

@test "a refusal from a custom endpoint fails instead of passing as an empty translation" {
  printf 'provider = "openai"\nmodel = "some-model"\n' >"$CONFIG"
  STUB_REFUSAL=1 run python3 "$SCRIPT" --quiet "hello"
  [ "$status" -eq 1 ]
  [[ "$output" == *"断られました"* ]]
}

@test "provider openai without a model is refused before anything is sent" {
  printf 'provider = "openai"\nbase_url = "https://gw.example/v1"\n' >"$CONFIG"
  run python3 "$SCRIPT" --quiet "hello"
  [ "$status" -eq 1 ]
  [[ "$output" == *"model"* ]]
  [ ! -e "$REQUEST" ]
}

@test "an Anthropic-compatible custom endpoint only moves the base URL" {
  printf 'base_url = "https://gw.example"\n' >"$CONFIG"
  run python3 "$SCRIPT" --quiet "hello"
  [ "$status" -eq 0 ]
  [ "$(cat "$REQUEST.base")" = "https://gw.example" ]
  [ "$(cat "$REQUEST.key")" = "sk-from-keychain:anthropic" ]
}
