#!/usr/bin/env bats

# Tests for hammerspoon/translate.py — what it sends to the API, against a
# stub SDK, since the real call needs a key and the Mac's clipboard and dialog
# tools. What must hold: the target language follows the text (Japanese →
# English, anything else → Japanese) unless --to fixes it, an image goes as
# a base64 block, and the key comes from the Keychain only — never from the
# environment, where every child process would see it.

bats_require_minimum_version 1.5.0

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
class APIStatusError(Exception):
    def __init__(self, message="boom", status_code=500):
        self.message, self.status_code = message, status_code
class AuthenticationError(APIStatusError): pass
class RateLimitError(APIStatusError): pass
class APIConnectionError(Exception): pass
def _raise_stub_error():
    if os.environ.get("STUB_ERROR"):
        raise globals()[os.environ["STUB_ERROR"]]()
class _Obj:
    def __init__(self, **kw): self.__dict__.update(kw)
class _Stream:
    # STUB_TEXT replaces the answer, for a test that needs a particular one.
    text_stream = [os.environ["STUB_TEXT"]] if os.environ.get("STUB_TEXT") else ["TRANS", "LATED"]
    def __enter__(self): return self
    def __exit__(self, *exc): return False
    def get_final_message(self):
        text = os.environ.get("STUB_TEXT") or "TRANSLATED"
        return _Obj(stop_reason="end_turn", content=[_Obj(type="text", text=text)])
class _Messages:
    def stream(self, **kw):
        with open(os.environ["REQUEST"], "w") as f:
            json.dump(kw, f)
        _raise_stub_error()
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
class APIStatusError(Exception):
    def __init__(self, message="boom", status_code=500):
        self.message, self.status_code = message, status_code
class AuthenticationError(APIStatusError): pass
class RateLimitError(APIStatusError): pass
class APIConnectionError(Exception): pass
def _raise_stub_error():
    if os.environ.get("STUB_ERROR"):
        raise globals()[os.environ["STUB_ERROR"]]()
class _Obj:
    def __init__(self, **kw): self.__dict__.update(kw)
class _Responses:
    def create(self, **kw):
        with open(os.environ["REQUEST"], "w") as f:
            json.dump(kw, f)
        _raise_stub_error()
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
  printf '#!/bin/sh\ncat >"$CLIPBOARD"\n' >"$TMP/bin/pbcopy"
  printf '#!/bin/sh\nexit 0\n' >"$TMP/bin/osascript"
  chmod +x "$TMP/bin/"*

  # HOME too: the config file and instructions are read from under it, and
  # the machine's own must not decide what these tests send. The interpreter
  # is pinned first, since a version manager's shim reads its state from HOME.
  ln -s "$(python3 -c 'import sys; print(sys.executable)')" "$TMP/bin/python3"
  mkdir -p "$TMP/home/.local/share/desktop-translate"
  CONFIG="$TMP/home/.local/share/desktop-translate/config.toml"
  STYLE="$TMP/home/.local/share/desktop-translate/style.md"
  LAST_REWRITE="$TMP/home/.local/share/desktop-translate/last-rewrite.json"
  EDITS="$TMP/home/.local/share/desktop-translate/rewrite-edits.jsonl"
  export CLIPBOARD="$TMP/clipboard"
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
  [[ "$output" == *"security add-generic-password -s desktop-translate -a anthropic -w" ]]
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

# Each SDK error the stub raises, and the message it must turn into.
api_errors_fail_with_their_message() {
  local error expected
  while read -r error expected; do
    STUB_ERROR="$error" run python3 "$SCRIPT" --quiet "hello"
    [ "$status" -eq 1 ] || { echo "$error: status $status"; return 1; }
    [[ "$output" == *"$expected"* ]] || { echo "$error: $output"; return 1; }
  done <<'EOF'
AuthenticationError API キーが無効です
RateLimitError レート制限に当たりました
APIStatusError API エラー 500: boom
APIConnectionError API に接続できません
EOF
}

@test "each API error fails with its own message" {
  api_errors_fail_with_their_message
}

@test "each API error from a custom endpoint fails with its own message" {
  printf 'provider = "openai"\nmodel = "some-model"\n' >"$CONFIG"
  api_errors_fail_with_their_message
}

# --rewrite: rough notes → a message in the user's voice, from a style file
# that stays on the machine, or in a plain voice without one.

request_system() {
  python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["system"])' "$REQUEST"
}

# One top-level field of the recorded request, as Python prints it; None when absent.
request_field() {
  python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get(sys.argv[2]))' "$REQUEST" "$1"
}

@test "--rewrite asks for the notes rewritten, not translated" {
  echo "Ends sentences with ー." >"$STYLE"
  run python3 "$SCRIPT" --quiet --rewrite "明日 MTG 15時→16時 / 資料あとで"
  [ "$status" -eq 0 ]
  [[ "$(request_text)" == "Rewrite these notes as one message."*"明日 MTG 15時→16時 / 資料あとで" ]]
  [[ "$(request_text)" != *"Translate"* ]]
}

@test "--rewrite puts the style file in the instructions, and forbids adding facts" {
  echo "Ends sentences with ー." >"$STYLE"
  run python3 "$SCRIPT" --quiet --rewrite "hello"
  [ "$status" -eq 0 ]
  [[ "$(request_system)" == *"Ends sentences with ー."* ]]
  [[ "$(request_system)" == *"add no facts that are not there"* ]]
}

@test "--rewrite without a style file still rewrites, as tidy bullets that add no facts" {
  run python3 "$SCRIPT" --quiet --rewrite "hello"
  [ "$status" -eq 0 ]
  [ "$output" = "TRANSLATED" ]
  [[ "$(request_system)" == *"Keep it as bullet points"* ]]
  [[ "$(request_system)" == *"add no facts that are not there"* ]]
  [[ "$(request_system)" != *"style guide"* ]]
}

@test "--rewrite copies the message, with the translation's key" {
  echo "Plain." >"$STYLE"
  run python3 "$SCRIPT" --quiet --rewrite --clipboard
  [ "$status" -eq 0 ]
  [ "$output" = "TRANSLATED" ]
  [[ "$(request_text)" == *"clipboard text"* ]]
  [ "$(cat "$CLIPBOARD")" = "TRANSLATED" ]
  [ "$(cat "$REQUEST.key")" = "sk-from-keychain:anthropic" ]
}

@test "--rewrite goes to a custom endpoint with the style in its instructions" {
  echo "Ends sentences with ー." >"$STYLE"
  printf 'provider = "openai"\nmodel = "some-model"\n' >"$CONFIG"
  run python3 "$SCRIPT" --quiet --rewrite "hello"
  [ "$status" -eq 0 ]
  python3 -c 'import json, sys; assert "Ends sentences with" in json.load(open(sys.argv[1]))["instructions"]' "$REQUEST"
}

@test "--rewrite with --to is refused" {
  echo "Plain." >"$STYLE"
  run python3 "$SCRIPT" --quiet --rewrite --to en "hello"
  [ "$status" -ne 0 ]
  [ ! -e "$REQUEST" ]
}

# --reply and --summarize: the same path as --rewrite, each with its own ask.

@test "--reply drafts a reply in the user's style, leaving decisions to them" {
  echo "Ends sentences with ー." >"$STYLE"
  run python3 "$SCRIPT" --quiet --reply "明日来られますか？"
  [ "$status" -eq 0 ]
  [[ "$(request_text)" == "Draft my reply to this message."*"明日来られますか？" ]]
  [[ "$(request_system)" == *"Ends sentences with ー."* ]]
  [[ "$(request_system)" == *"decide nothing on the user's behalf"* ]]
}

@test "--reply without a style file fails before anything is sent" {
  run python3 "$SCRIPT" --quiet --reply "hello"
  [ "$status" -eq 1 ]
  [[ "$output" == *"style.md"* ]]
  [ ! -e "$REQUEST" ]
}

@test "--summarize needs no style file and asks for Japanese whatever the text" {
  run python3 "$SCRIPT" --quiet --summarize "A long English thread"
  [ "$status" -eq 0 ]
  [[ "$(request_text)" == "Summarize this."*"A long English thread" ]]
  [[ "$(request_system)" == *"in Japanese"* ]]
  [[ "$(request_system)" == *"at most five"*"half the length"* ]]
  [[ "$(request_system)" != *"Style guide"* ]]
}

# The popup shows text as it is: on the Mac both models bolded labels with **.
@test "the written jobs ask for plain text; translation and proofreading keep the text's own marks" {
  echo "Plain." >"$STYLE"
  local job
  for job in --rewrite --reply --summarize; do
    run python3 "$SCRIPT" --quiet "$job" "hello"
    [ "$status" -eq 0 ] || { echo "$job: $output"; return 1; }
    [[ "$(request_system)" == *"no Markdown"* ]] || { echo "$job asks for none"; return 1; }
  done
  run python3 "$SCRIPT" --quiet --proofread "hello"
  [[ "$(request_system)" != *"no Markdown"* ]]
  run python3 "$SCRIPT" --quiet "hello"
  [[ "$(request_system)" != *"no Markdown"* ]]
}

@test "two jobs at once are refused" {
  echo "Plain." >"$STYLE"
  run python3 "$SCRIPT" --quiet --rewrite --summarize "hello"
  [ "$status" -ne 0 ]
  [ ! -e "$REQUEST" ]
}

@test "--proofread fixes slips only, without the style file" {
  run python3 "$SCRIPT" --quiet --proofread "明日わ休みです"
  [ "$status" -eq 0 ]
  [[ "$(request_text)" == "Proofread this."*"明日わ休みです" ]]
  [[ "$(request_system)" == *"Change nothing else"* ]]
  [[ "$(request_system)" != *"Style guide"* ]]
}

# --diagram: the answer is an SVG for the popup to show and copy as an image.

@test "--diagram asks for one SVG and leaves the clipboard to the popup" {
  STUB_TEXT='<svg width="480"><rect/></svg>' run python3 "$SCRIPT" --quiet --diagram "A → B → C"
  [ "$status" -eq 0 ]
  [ "$output" = '<svg width="480"><rect/></svg>' ]
  [[ "$(request_text)" == "Draw this as a diagram."*"A → B → C" ]]
  [[ "$(request_system)" == *"Output only SVG markup"* ]]
  [[ "$(request_system)" == *"No script"* ]]
  [ ! -e "$CLIPBOARD" ]
}

@test "--diagram fails when the answer is not an SVG" {
  STUB_TEXT='Here is your diagram: <svg></svg>' run python3 "$SCRIPT" --quiet --diagram "A → B"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SVG 以外"* ]]
}

@test "--diagram cut short says so, rather than that it was not an SVG" {
  printf 'provider = "openai"\nmodel = "some-model"\n' >"$CONFIG"
  STUB_INCOMPLETE=1 run python3 "$SCRIPT" --quiet --diagram "A → B"
  [ "$status" -eq 1 ]
  [[ "$output" == *"図が長すぎて"* ]]
}

@test "--wait makes the client before the job arrives, then runs the job it finds" {
  python3 "$SCRIPT" --wait "$TMP/job.json" >"$TMP/out" 2>"$TMP/err" &
  for _ in $(seq 50); do [ -e "$REQUEST.key" ] && break; sleep 0.1; done
  # Read before the job goes in, but checked after: a failed check here
  # would leave the waiting script holding the test for JOB_WAIT.
  local made=no sent=no
  [ -e "$REQUEST.key" ] && made=yes
  [ -e "$REQUEST" ] && sent=yes
  echo '["--quiet", "--summarize", "--clipboard"]' >"$TMP/job.json"
  wait $!
  [ "$made" = yes ]
  [ "$sent" = no ]
  [ "$(cat "$TMP/out")" = "TRANSLATED" ]
  [[ "$(request_text)" == "Summarize this."*"clipboard text" ]]
  [ ! -e "$TMP/job.json" ]
}

@test "--wait sends nothing when no job comes in time" {
  cp "$SCRIPT" "$TMP/translate.py"
  # perl, not sed -i: BSD sed on a Mac takes the script for a backup suffix.
  perl -pi -e 's/^JOB_WAIT = .*/JOB_WAIT = 0.2/' "$TMP/translate.py"
  run python3 "$TMP/translate.py" --wait "$TMP/never.json"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  [ ! -e "$REQUEST" ]
}

@test "--timing says when the first words came, after the answer" {
  run python3 "$SCRIPT" --quiet --timing "hello"
  [ "$status" -eq 0 ]
  [[ "$output" == "TRANSLATED"*"最初の文字 "*"s / 全体 "*"claude-opus-5-5"* ]]
}

@test "a job given Haiku in the config asks for no thinking and no fallback; the others keep theirs" {
  printf '[models]\nproofread = "claude-haiku-5-5"\n' >"$CONFIG"
  run python3 "$SCRIPT" --quiet --proofread "hello"
  [ "$status" -eq 0 ]
  [ "$(request_field model)" = "claude-haiku-5-5" ]
  [ "$(request_field thinking)" = "{'type': 'disabled'}" ]
  [ "$(request_field fallbacks)" = "None" ]
  run python3 "$SCRIPT" --quiet "hello"
  [ "$(request_field model)" = "claude-opus-5-5" ]
  [ "$(request_field thinking)" = "None" ]
  [ "$(request_field fallbacks)" = "default" ]
}

@test "a summary goes to Haiku unless the config names a model" {
  run python3 "$SCRIPT" --quiet --summarize "hello"
  [ "$status" -eq 0 ]
  [ "$(request_field model)" = "claude-haiku-5-5" ]
  printf 'model = "claude-opus-5-5"\n' >"$CONFIG"
  run python3 "$SCRIPT" --quiet --summarize "hello"
  [ "$(request_field model)" = "claude-opus-5-5" ]
}

@test "an answer from a job's faster model says so on stderr, and --best asks the default model" {
  run --separate-stderr python3 "$SCRIPT" --quiet --summarize "hello"
  [ "$status" -eq 0 ]
  [ "$output" = "TRANSLATED" ]
  [ "$stderr" = "@fast-model claude-haiku-5-5" ]
  run --separate-stderr python3 "$SCRIPT" --quiet --summarize --best "hello"
  [ "$status" -eq 0 ]
  [ "$(request_field model)" = "claude-opus-5-5" ]
  [ "$stderr" = "" ]
}

@test "the config's [models] counts as a faster model too" {
  printf '[models]\nproofread = "claude-haiku-5-5"\n' >"$CONFIG"
  run --separate-stderr python3 "$SCRIPT" --quiet --proofread "hello"
  [ "$status" -eq 0 ]
  [ "$stderr" = "@fast-model claude-haiku-5-5" ]
}

@test "the default model's answer says nothing about a faster one" {
  run --separate-stderr python3 "$SCRIPT" --quiet "hello"
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
}

# Edits to a rewrite: what the user changed in the popup before copying it is
# kept on the machine, and the latest few go back in as examples.

mode_of() {
  python3 -c 'import os, sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$1"
}

# record_edit NOTES DRAFT FINAL: one logged edit, as the popup would leave it.
record_edit() {
  printf '{"notes": "%s", "draft": "%s"}' "$1" "$2" >"$LAST_REWRITE"
  printf '%s' "$3" | python3 "$SCRIPT" --record-edit
}

@test "--rewrite leaves its notes and draft for --record-edit, readable only by the user" {
  run python3 "$SCRIPT" --quiet --rewrite "明日 MTG 16時"
  [ "$status" -eq 0 ]
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d == {"notes": "明日 MTG 16時", "draft": "TRANSLATED"}, d
' "$LAST_REWRITE"
  [ "$(mode_of "$LAST_REWRITE")" = 0o600 ]
}

@test "--record-edit logs notes, draft and the edited text, readable only by the user" {
  python3 "$SCRIPT" --quiet --rewrite "明日 MTG 16時"
  run bash -c 'printf "・明日の定例は16時からです" | python3 "$0" --record-edit' "$SCRIPT"
  [ "$status" -eq 0 ]
  python3 -c '
import json, sys
lines = open(sys.argv[1]).read().splitlines()
want = [{"notes": "明日 MTG 16時", "draft": "TRANSLATED", "final": "・明日の定例は16時からです"}]
assert [json.loads(l) for l in lines] == want, lines
' "$EDITS"
  [ "$(mode_of "$EDITS")" = 0o600 ]
}

@test "--record-edit logs nothing when the draft went out unchanged" {
  python3 "$SCRIPT" --quiet --rewrite "hello"
  run bash -c 'printf "TRANSLATED\n" | python3 "$0" --record-edit' "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$EDITS" ]
}

@test "--record-edit with no rewrite before it logs nothing" {
  run bash -c 'printf "edited" | python3 "$0" --record-edit' "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$EDITS" ]
}

@test "--rewrite shows the latest five edits as examples, and none for a translation or a reply" {
  for i in 1 2 3 4 5 6 7; do record_edit "notes$i" "draft$i" "final$i"; done
  run python3 "$SCRIPT" --quiet --rewrite "hello"
  [ "$status" -eq 0 ]
  [[ "$(request_system)" == *"final3"*"final7"* ]]
  [[ "$(request_system)" != *"final2"* ]]
  run python3 "$SCRIPT" --quiet "hello"
  [[ "$(request_system)" != *"final7"* ]]
  echo "Plain." >"$STYLE"
  run python3 "$SCRIPT" --quiet --reply "hello"
  [[ "$(request_system)" != *"final7"* ]]
}
