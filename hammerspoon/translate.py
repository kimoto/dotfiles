#!/usr/bin/env python3
"""Desktop translation with Claude, called by hammerspoon/translate.lua.

Mirrors the DeepL app's shortcuts (see KEYBINDINGS.md, "Translation") but
runs on the Claude API: images work without a separate OCR step, and the
style of the translation can be steered (instructions file below).

Usage:
  translate.py --clipboard          translate the clipboard (⌘C+C)
  translate.py --screen             select a region, translate the text in it
  translate.py --image foo.png      translate the text in an image file
  translate.py --to en "..."        fix the target language; by default
                                    Japanese becomes English, anything else Japanese
  translate.py --rewrite --clipboard
                                    rewrite rough notes as a message in the
                                    user's own style (style file below)
  echo "..." | translate.py         stdin, when not --clipboard

The result goes to stdout, the clipboard, and a dialog (--quiet: no dialog).

One-time setup on a Mac (nothing in bin/mklink.sh does this):
  python3 -m venv ~/.local/share/desktop-translate
  ~/.local/share/desktop-translate/bin/pip install -U anthropic
  security add-generic-password -s desktop-translate -a anthropic -w
    (prompts for the key, so it never lands in shell history)
  then grant Hammerspoon Accessibility and Screen Recording, and turn off
  the DeepL app's own shortcuts, or both apps answer ⌘C+C.

Optional: a custom endpoint in ~/.local/share/desktop-translate/config.toml
(it stays on the machine, so the endpoint's address never reaches this repo):
  provider = "openai"          # OpenAI Responses API; "anthropic" by default
  base_url = "https://llm.example/v1"
  model = "..."                # required for "openai"
  reasoning_effort = "low"     # optional, for reasoning models only
"openai" needs `pip install -U openai` in the same venv, and its key under
its own account: security add-generic-password -s desktop-translate -a openai -w

The key is read from the Keychain only, inside this process. Never from the
environment: every child this script starts would see it there, and an
exported ANTHROPIC_API_KEY also switches Claude Code to API billing.

Optional: extra instructions (a glossary, a register) in
~/.local/share/desktop-translate/instructions.txt are appended to the system
prompt. Not under ~/.config, which is this repo's config/.

Optional: ~/.local/share/desktop-translate/style.md for --rewrite: how the
user writes (endings, greetings, emoji, line breaks) and a few real messages
of theirs. It stays on the machine because it is the user's own writing, and
this repo is public. Without it, --rewrite writes a plain, polite message.
"""

import argparse
import base64
import contextlib
import os
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

KEYCHAIN_SERVICE = "desktop-translate"
CONFIG = Path.home() / ".local/share/desktop-translate/config.toml"
PROVIDERS = ("anthropic", "openai")
ANTHROPIC_MODEL = "claude-opus-5-5"
# Thinking cannot be turned off on this model; low effort keeps the wait short.
EFFORT = os.environ.get("DESKTOP_TRANSLATE_EFFORT", "low")
EXTRA_INSTRUCTIONS = Path.home() / ".local/share/desktop-translate/instructions.txt"
STYLE = Path.home() / ".local/share/desktop-translate/style.md"

LANG_NAMES = {"ja": "Japanese", "en": "English"}

SYSTEM = """You are a translation tool on the user's desktop. Output only the translation:
no preamble, no notes, no quotation marks around it. Keep the original line breaks,
lists, code, URLs, file paths and product names as they are. Translate naturally
rather than word for word."""

REWRITE_SYSTEM = """You turn the user's rough notes into a chat message they will send as their own.
Output only the message: no preamble, no notes, no quotation marks around it.
Write in the language of the notes.
Keep every point in the notes and add no facts that are not there: no dates, numbers,
names, promises or apologies the notes do not give. Keep URLs, code and names as they are.
"""

REWRITE_VOICE = "Write in the user's voice as this style guide describes it:\n"
# Without a style file: a voice that fits most work chats and invents no persona.
REWRITE_PLAIN_VOICE = ("Write it as a plain, polite chat message to colleagues, "
                       "with no greeting or sign-off the notes do not ask for.")

REWRITE_INSTRUCTION = "Rewrite these notes as one message."


def load_config() -> dict:
    if not CONFIG.exists():
        return {"provider": "anthropic"}
    try:
        config = tomllib.loads(CONFIG.read_text(encoding="utf-8"))
    except tomllib.TOMLDecodeError as e:
        fail(f"設定ファイルを読めません（{CONFIG}）: {e}")
    config.setdefault("provider", "anthropic")
    if config["provider"] not in PROVIDERS:
        fail(f"provider は {' か '.join(PROVIDERS)} です（{CONFIG}）。")
    if config["provider"] == "openai" and not config.get("model"):
        fail(f'provider = "openai" には model が要ります（{CONFIG}）。')
    return config


def api_key(provider: str) -> str:
    # The account names the provider: with only -s, the first of several
    # entries under the service would answer, whichever provider it was for.
    try:
        key = subprocess.run(
            ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-a", provider, "-w"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        if key:
            return key
    except (FileNotFoundError, subprocess.CalledProcessError):
        pass
    fail(f"API キーが見つかりません（Keychain の {KEYCHAIN_SERVICE}、アカウント {provider}）。")


def is_mostly_japanese(text: str) -> bool:
    ja = sum(1 for c in text if "\u3040" <= c <= "\u30ff" or "\u4e00" <= c <= "\u9fff")
    latin = sum(1 for c in text if c.isascii() and c.isalpha())
    # Japanese prose is full of English product names; a third is enough.
    return ja > 0 and ja >= latin * 0.3


def target_for(text: str | None, forced: str | None) -> str:
    if forced:
        return forced
    if text is None:  # an image: only the model can see which language it is
        return "auto"
    return "en" if is_mostly_japanese(text) else "ja"


def instruction(target: str) -> str:
    if target == "auto":
        return ("Translate the text in this image. If it is mostly Japanese, translate into "
                "English; otherwise translate into Japanese. If there is no text, say so in Japanese.")
    return f"Translate the following into {LANG_NAMES[target]}."


def rewrite_system_prompt() -> str:
    if not STYLE.exists():
        return REWRITE_SYSTEM + "\n" + REWRITE_PLAIN_VOICE
    return REWRITE_SYSTEM + "\n" + REWRITE_VOICE + STYLE.read_text(encoding="utf-8").strip()


def system_prompt() -> str:
    if EXTRA_INSTRUCTIONS.exists():
        return SYSTEM + "\n\n" + EXTRA_INSTRUCTIONS.read_text(encoding="utf-8").strip()
    return SYSTEM


def emit(chunk: str) -> None:
    sys.stdout.write(chunk)
    sys.stdout.flush()


@contextlib.contextmanager
def api_errors(sdk):
    """Turn the SDK's errors into a message; both SDKs name them alike."""
    try:
        yield
    except sdk.AuthenticationError:
        fail("API キーが無効です。")
    except sdk.RateLimitError:
        fail("レート制限に当たりました。少し待ってから再実行してください。")
    except sdk.APIStatusError as e:
        fail(f"API エラー {e.status_code}: {e.message}")
    except sdk.APIConnectionError:
        fail("API に接続できません。")


def translate_anthropic(content: list, system: str, config: dict) -> tuple[str, bool]:
    import anthropic

    client = anthropic.Anthropic(api_key=api_key("anthropic"), base_url=config.get("base_url"))
    model = os.environ.get("DESKTOP_TRANSLATE_MODEL") or config.get("model") or ANTHROPIC_MODEL
    # fallbacks: a safety classifier's false positive on ordinary text is
    # retried on the model Anthropic recommends instead of failing.
    with api_errors(anthropic), client.beta.messages.stream(
        model=model,
        max_tokens=16000,
        output_config={"effort": EFFORT},
        betas=["server-side-fallback-2026-07-01"],
        fallbacks="default",
        system=system,
        messages=[{"role": "user", "content": content}],
    ) as stream:
        for chunk in stream.text_stream:
            emit(chunk)
        response = stream.get_final_message()

    if response.stop_reason == "refusal":
        fail("この内容は翻訳を断られました。")
    text = "".join(b.text for b in response.content if b.type == "text")
    return text, response.stop_reason == "max_tokens"


def openai_input(content: list) -> list:
    """The same request, as the Responses API's input items."""
    parts = []
    for block in content:
        if block["type"] == "text":
            parts.append({"type": "input_text", "text": block["text"]})
        else:
            source = block["source"]
            parts.append({"type": "input_image", "detail": "high",
                          "image_url": f"data:{source['media_type']};base64,{source['data']}"})
    return [{"role": "user", "content": parts}]


def translate_openai(content: list, system: str, config: dict) -> tuple[str, bool]:
    import openai

    client = openai.OpenAI(api_key=api_key("openai"), base_url=config.get("base_url"))
    params = {"model": config["model"], "instructions": system,
              "input": openai_input(content), "max_output_tokens": 16000, "stream": True}
    if config.get("reasoning_effort"):
        params["reasoning"] = {"effort": config["reasoning_effort"]}
    pieces, truncated = [], False
    with api_errors(openai):
        for event in client.responses.create(**params):
            if event.type == "response.output_text.delta":
                emit(event.delta)
                pieces.append(event.delta)
            elif event.type == "response.refusal.done":
                fail(f"この内容は翻訳を断られました。{event.refusal}")
            elif event.type == "response.incomplete":
                details = event.response.incomplete_details
                if details and details.reason == "content_filter":
                    fail("この内容は翻訳を断られました。")
                truncated = True
            elif event.type == "response.failed":
                error = event.response.error
                fail(f"API エラー: {error.message if error else '理由不明'}")
            elif event.type == "error":
                fail(f"API エラー: {event.message}")
    return "".join(pieces), truncated


def translate(content: list, system: str) -> str:
    """Translate, writing the text to stdout as it arrives; return all of it.

    Streamed so the popup can show the first words while the rest is still
    being written: a long passage otherwise waits for its last token.
    """
    config = load_config()
    run = translate_openai if config["provider"] == "openai" else translate_anthropic
    text, truncated = run(content, system, config)
    text = text.strip()
    if truncated:
        cut = "\n\n（長すぎて途中で切れました）"
        emit(cut)
        text += cut
    emit("\n")
    return text


def screenshot() -> Path | None:
    fd, name = tempfile.mkstemp(suffix=".png")
    os.close(fd)
    path = Path(name)
    # -i: interactive region (Esc cancels), -x: no shutter sound
    subprocess.run(["screencapture", "-i", "-x", str(path)], check=False)
    if path.stat().st_size == 0:
        path.unlink()
        return None
    return path


def image_block(path: Path) -> dict:
    media = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
             ".gif": "image/gif", ".webp": "image/webp"}.get(path.suffix.lower())
    if not media:
        fail(f"対応していない画像形式です: {path.suffix}")
    data = base64.standard_b64encode(path.read_bytes()).decode("utf-8")
    return {"type": "image", "source": {"type": "base64", "media_type": media, "data": data}}


def read_text(args) -> str:
    if args.text:
        return " ".join(args.text)
    if not args.clipboard and not sys.stdin.isatty():
        piped = sys.stdin.read()
        if piped.strip():
            return piped
    return subprocess.run(["pbpaste"], capture_output=True, text=True, check=False).stdout


def show(text: str, quiet: bool, title: str) -> None:
    """Copy the result, which translate() already wrote to stdout."""
    subprocess.run(["pbcopy"], input=text, text=True, check=False)
    if not quiet:
        # The text goes in as argv, so AppleScript string escaping never applies.
        subprocess.run([
            "osascript",
            "-e", "on run argv",
            "-e", 'display dialog (item 1 of argv) with title (item 2 of argv) buttons {"OK"} default button 1',
            "-e", "end run",
            text, f"{title}（コピー済み）",
        ], capture_output=True, check=False)


def fail(message: str):
    print(message, file=sys.stderr)
    subprocess.run(["osascript", "-e", "on run argv", "-e",
                    'display notification (item 1 of argv) with title "翻訳"',
                    "-e", "end run", message], capture_output=True, check=False)
    sys.exit(1)


def main() -> None:
    p = argparse.ArgumentParser(description="Desktop translation with Claude")
    p.add_argument("text", nargs="*", help="text to translate (default: stdin, then the clipboard)")
    p.add_argument("--clipboard", action="store_true", help="translate the clipboard, ignoring stdin")
    # Exclusive: the screenshot is deleted afterwards, and with both given
    # that would be the user's own --image file.
    source = p.add_mutually_exclusive_group()
    source.add_argument("--screen", action="store_true", help="select a screen region and translate its text")
    source.add_argument("--image", type=Path, help="translate the text in an image file")
    # Rewriting keeps the language, so it never goes with a target or an image.
    source.add_argument("--rewrite", action="store_true", help="rewrite notes as a message in the user's style")
    p.add_argument("--to", choices=["ja", "en"], help="target language (default: automatic)")
    p.add_argument("--quiet", action="store_true", help="no dialog")
    args = p.parse_args()
    if args.rewrite and args.to:
        p.error("--rewrite keeps the language; it does not take --to")

    if args.rewrite:
        system = rewrite_system_prompt()
        text = read_text(args)
        if not text.strip():
            fail("書き換える文がありません。")
        content = [{"type": "text", "text": f"{REWRITE_INSTRUCTION}\n\n{text}"}]
        show(translate(content, system), args.quiet, "清書")
        return

    if args.screen or args.image:
        path = args.image or screenshot()
        if path is None:
            return  # region selection cancelled with Esc
        try:
            content = [image_block(path), {"type": "text", "text": instruction(target_for(None, args.to))}]
        finally:
            if args.screen:
                path.unlink()
    else:
        text = read_text(args)
        if not text.strip():
            fail("訳す文がありません。")
        content = [{"type": "text", "text": f"{instruction(target_for(text, args.to))}\n\n{text}"}]

    show(translate(content, system_prompt()), args.quiet, "翻訳")


if __name__ == "__main__":
    main()
