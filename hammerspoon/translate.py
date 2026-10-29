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
  translate.py --reply --clipboard  draft a reply to a message, in that style
  translate.py --summarize --clipboard
                                    summarize the text in Japanese
  translate.py --proofread --clipboard
                                    fix typos and wrong words, nothing else
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

--rewrite and --reply write in the user's voice from
~/.local/share/desktop-translate/style.md: how the user writes (endings,
greetings, emoji, line breaks) and a few real messages of theirs. It stays on
the machine because it is the user's own writing, and this repo is public.
Without it, --rewrite tidies the notes into polite bullet points that a reader
who did not write them can follow, and --reply fails rather than guess a voice.

A rewrite edited in the popup before copying is logged, with its notes and
draft, in ~/.local/share/desktop-translate/rewrite-edits.jsonl (--record-edit;
last-rewrite.json holds the one being edited). Both are readable only by the
user and outside any repository: they hold real messages. The latest few
edits go to the API with each rewrite, as examples of what the user changes.
"""

import argparse
import base64
import contextlib
import json
import os
import subprocess
import sys
import tempfile
import tomllib
from dataclasses import dataclass
from pathlib import Path

KEYCHAIN_SERVICE = "desktop-translate"
CONFIG = Path.home() / ".local/share/desktop-translate/config.toml"
PROVIDERS = ("anthropic", "openai")
ANTHROPIC_MODEL = "claude-opus-5-5"
# Thinking cannot be turned off on this model; low effort keeps the wait short.
EFFORT = os.environ.get("DESKTOP_TRANSLATE_EFFORT", "low")
EXTRA_INSTRUCTIONS = Path.home() / ".local/share/desktop-translate/instructions.txt"
STYLE = Path.home() / ".local/share/desktop-translate/style.md"
LAST_REWRITE = Path.home() / ".local/share/desktop-translate/last-rewrite.json"
REWRITE_EDITS = Path.home() / ".local/share/desktop-translate/rewrite-edits.jsonl"
# Enough to show the user's habits; every one goes out with each rewrite.
EXAMPLE_EDITS = 5

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

VOICE = "Write in the user's voice as this style guide describes it:\n"
# Without a style file: the user's own preference, bullets, made readable for
# someone who did not write the notes, with no persona invented.
REWRITE_PLAIN_VOICE = ("Keep it as bullet points, one point each, in short polite sentences that someone "
                       "who did not write the notes can follow. No greeting, sign-off or request "
                       "the notes do not ask for.")

REPLY_SYSTEM = """You draft the user's reply to a chat message someone sent them.
Output only the reply: no preamble, no notes, no quotation marks around it.
Write in the language of the message.
Answer what the message asks, and decide nothing on the user's behalf: where the reply needs
a fact, a date or a yes/no the user has not given, leave a short placeholder in 【】 instead.
"""

SUMMARY_SYSTEM = """You summarize text for the user on their desktop. Output only the summary, in Japanese,
whatever the language of the text: a one-line gist, then the points that matter as short
bullets. Keep decisions, dates, numbers, names and open questions; drop greetings and
repetition. Add nothing that is not in the text."""

PROOFREAD_SYSTEM = """You proofread the user's text before they send it. Output only the corrected text:
no preamble, no list of changes, no quotation marks around it. Fix typos, wrong kanji
conversions, missing or doubled characters, and grammar slips. Change nothing else: keep the
wording, tone, line breaks and emoji. If there is nothing to fix, output the text unchanged."""


@dataclass(frozen=True)
class Task:
    """A job that keeps the text's own language, unlike translation."""
    system: str
    instruction: str
    needs_style: bool  # writes in the user's voice, from the style file
    title: str  # the dialog's title
    empty: str  # what fail() says when there is no text
    plain_voice: str | None = None  # the voice without a style file; None fails instead
    learns_edits: bool = False  # the popup's edits to it come back as examples


TASKS = {
    "rewrite": Task(REWRITE_SYSTEM, "Rewrite these notes as one message.", True, "清書",
                    "書き換える文がありません。", plain_voice=REWRITE_PLAIN_VOICE, learns_edits=True),
    "reply": Task(REPLY_SYSTEM, "Draft my reply to this message.", True, "返信案",
                  "返信する相手のメッセージがありません。"),
    "summarize": Task(SUMMARY_SYSTEM, "Summarize this.", False, "要約", "要約する文がありません。"),
    "proofread": Task(PROOFREAD_SYSTEM, "Proofread this.", False, "誤字チェック", "見直す文がありません。"),
}

EDITS_INTRO = ("Earlier drafts and what the user sent instead. Follow the preferences these edits "
               "show; never reuse their content:\n\n")


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


def task_system_prompt(task: Task) -> str:
    if not task.needs_style:
        return task.system
    if STYLE.exists():
        prompt = task.system + "\n" + VOICE + STYLE.read_text(encoding="utf-8").strip()
    elif task.plain_voice:
        prompt = task.system + "\n" + task.plain_voice
    else:
        fail(f"文体メモがありません（{STYLE}）。自分の文面の特徴と手本を数通書いてください。")
    edits = recent_edits() if task.learns_edits else []
    if edits:
        prompt += "\n\n" + EDITS_INTRO + "\n\n".join(
            f"Notes:\n{e['notes']}\nDraft:\n{e['draft']}\nWhat the user sent instead:\n{e['final']}"
            for e in edits)
    return prompt


def write_private(path: Path, text: str, append: bool = False) -> None:
    """Write a file only the user can read: it holds their own messages."""
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | (os.O_APPEND if append else os.O_TRUNC), 0o600)
    os.fchmod(fd, 0o600)  # a file that already existed keeps its old mode otherwise
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)


def recent_edits() -> list[dict]:
    if not REWRITE_EDITS.exists():
        return []
    edits = []
    for line in REWRITE_EDITS.read_text(encoding="utf-8").splitlines()[-EXAMPLE_EDITS:]:
        with contextlib.suppress(json.JSONDecodeError):
            edit = json.loads(line)
            if {"notes", "draft", "final"} <= edit.keys():
                edits.append(edit)
    return edits


def record_edit(final: str) -> None:
    """Pair the text the user copied from the popup with the rewrite it came from.

    Quiet when there is nothing to learn: no rewrite before it, or the draft
    went out as it was.
    """
    final = final.strip()
    try:
        last = json.loads(LAST_REWRITE.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return
    draft = str(last.get("draft", "")).strip()
    if not final or final == draft:
        return
    entry = {"notes": last.get("notes", ""), "draft": draft, "final": final}
    write_private(REWRITE_EDITS, json.dumps(entry, ensure_ascii=False) + "\n", append=True)



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
    # These keep the language, so they never go with a target or an image.
    source.add_argument("--rewrite", dest="task", action="store_const", const="rewrite",
                        help="rewrite notes as a message in the user's style")
    source.add_argument("--reply", dest="task", action="store_const", const="reply",
                        help="draft a reply to a message, in the user's style")
    source.add_argument("--summarize", dest="task", action="store_const", const="summarize",
                        help="summarize the text in Japanese")
    source.add_argument("--proofread", dest="task", action="store_const", const="proofread",
                        help="fix typos and wrong words, nothing else")
    p.add_argument("--to", choices=["ja", "en"], help="target language (default: automatic)")
    p.add_argument("--quiet", action="store_true", help="no dialog")
    p.add_argument("--record-edit", action="store_true",
                   help="log the last rewrite as the user edited it (the edited text on stdin)")
    args = p.parse_args()
    if args.task and args.to:
        p.error(f"--{args.task} keeps the language; it does not take --to")

    if args.record_edit:
        record_edit(sys.stdin.read())
        return

    if args.task:
        task = TASKS[args.task]
        system = task_system_prompt(task)
        text = read_text(args)
        if not text.strip():
            fail(task.empty)
        content = [{"type": "text", "text": f"{task.instruction}\n\n{text}"}]
        result = translate(content, system)
        if task.learns_edits:
            write_private(LAST_REWRITE, json.dumps({"notes": text.strip(), "draft": result}, ensure_ascii=False))
        show(result, args.quiet, task.title)
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
