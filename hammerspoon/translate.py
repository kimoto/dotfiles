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
  echo "..." | translate.py         stdin, when not --clipboard

The result goes to stdout, the clipboard, and a dialog (--quiet: no dialog).

One-time setup on a Mac (nothing in bin/mklink.sh does this):
  python3 -m venv ~/.local/share/desktop-translate
  ~/.local/share/desktop-translate/bin/pip install -U anthropic
  security add-generic-password -s desktop-translate -a anthropic -w
    (prompts for the key, so it never lands in shell history)
  then grant Hammerspoon Accessibility and Screen Recording, and turn off
  the DeepL app's own shortcuts, or both apps answer ⌘C+C.

The key is read from the Keychain only, inside this process. Never from the
environment: every child this script starts would see it there, and an
exported ANTHROPIC_API_KEY also switches Claude Code to API billing.

Optional: extra instructions (a glossary, a register) in
~/.local/share/desktop-translate/instructions.txt are appended to the system
prompt. Not under ~/.config, which is this repo's config/.
"""

import argparse
import base64
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import anthropic

KEYCHAIN_SERVICE = "desktop-translate"
MODEL = os.environ.get("DESKTOP_TRANSLATE_MODEL", "claude-opus-5-5")
# Thinking cannot be turned off on this model; low effort keeps the wait short.
EFFORT = os.environ.get("DESKTOP_TRANSLATE_EFFORT", "low")
EXTRA_INSTRUCTIONS = Path.home() / ".local/share/desktop-translate/instructions.txt"

LANG_NAMES = {"ja": "Japanese", "en": "English"}

SYSTEM = """You are a translation tool on the user's desktop. Output only the translation:
no preamble, no notes, no quotation marks around it. Keep the original line breaks,
lists, code, URLs, file paths and product names as they are. Translate naturally
rather than word for word."""


def api_key() -> str:
    try:
        key = subprocess.run(
            ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        if key:
            return key
    except (FileNotFoundError, subprocess.CalledProcessError):
        pass
    fail("API キーが見つかりません（Keychain の desktop-translate）。")


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


def system_prompt() -> str:
    if EXTRA_INSTRUCTIONS.exists():
        return SYSTEM + "\n\n" + EXTRA_INSTRUCTIONS.read_text(encoding="utf-8").strip()
    return SYSTEM


def translate(content: list) -> str:
    """Translate, writing the text to stdout as it arrives; return all of it.

    Streamed so the popup can show the first words while the rest is still
    being written: a long passage otherwise waits for its last token.
    """
    client = anthropic.Anthropic(api_key=api_key())
    try:
        # fallbacks: a safety classifier's false positive on ordinary text is
        # retried on the model Anthropic recommends instead of failing.
        with client.beta.messages.stream(
            model=MODEL,
            max_tokens=16000,
            output_config={"effort": EFFORT},
            betas=["server-side-fallback-2026-07-01"],
            fallbacks="default",
            system=system_prompt(),
            messages=[{"role": "user", "content": content}],
        ) as stream:
            for chunk in stream.text_stream:
                sys.stdout.write(chunk)
                sys.stdout.flush()
            response = stream.get_final_message()
    except anthropic.AuthenticationError:
        fail("API キーが無効です。")
    except anthropic.RateLimitError:
        fail("レート制限に当たりました。少し待ってから再実行してください。")
    except anthropic.APIStatusError as e:
        fail(f"API エラー {e.status_code}: {e.message}")
    except anthropic.APIConnectionError:
        fail("API に接続できません。")

    if response.stop_reason == "refusal":
        fail("この内容は翻訳を断られました。")
    text = "".join(b.text for b in response.content if b.type == "text").strip()
    if response.stop_reason == "max_tokens":
        cut = "\n\n（長すぎて途中で切れました）"
        sys.stdout.write(cut)
        text += cut
    sys.stdout.write("\n")
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


def show(text: str, quiet: bool) -> None:
    """Copy the translation, which translate() already wrote to stdout."""
    subprocess.run(["pbcopy"], input=text, text=True, check=False)
    if not quiet:
        # The text goes in as argv, so AppleScript string escaping never applies.
        subprocess.run([
            "osascript",
            "-e", "on run argv",
            "-e", 'display dialog (item 1 of argv) with title "翻訳（コピー済み）" buttons {"OK"} default button 1',
            "-e", "end run",
            text,
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
    p.add_argument("--screen", action="store_true", help="select a screen region and translate its text")
    p.add_argument("--image", type=Path, help="translate the text in an image file")
    p.add_argument("--to", choices=["ja", "en"], help="target language (default: automatic)")
    p.add_argument("--quiet", action="store_true", help="no dialog")
    args = p.parse_args()

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

    show(translate(content), args.quiet)


if __name__ == "__main__":
    main()
