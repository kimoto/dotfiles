#!/usr/bin/env python3
"""MCP server (stdio) that lets an AI client on this Mac use the Guide spoon.

Each tool is one request to Hammerspoon on 127.0.0.1, with the token from the
endpoint file the spoon writes at start. The spoon checks every request again,
so this file only translates; it holds no rule of its own about what is allowed.
Standard library only, so the macOS python3 runs it with nothing installed.

Register it once per client, e.g. for Claude Code:
  claude mcp add --scope user guide -- python3 ~/.hammerspoon/Spoons/Guide.spoon/guide_mcp.py
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

ENDPOINT = os.environ.get("GUIDE_ENDPOINT") or os.path.expanduser("~/.local/state/guide/endpoint")
# The newest revision this speaks; an older one a client asks for is answered in kind.
PROTOCOLS = ["2025-06-18", "2025-03-26", "2024-11-05"]
# Every reply from the spoon comes from its main thread; a few seconds means Hammerspoon is stuck.
HTTP_TIMEOUT = 5
# How often ask checks for the owner's click: under the 0.1 s a person notices, not by much.
POLL_SECONDS = 0.25

TARGET = {
    "type": "object",
    "description": (
        "What to point at. {app} is that app's front window; {app, text} is the first button, field or "
        "label in it whose visible text contains text, as shown on screen in the Mac's language (a Japanese "
        "Mac shows ダウンロード, not Downloads); {x, y} is a point and {x, y, w, h} a rectangle, in "
        "screen points with the origin at the top left of the main screen (guide_status lists screens and "
        "window frames)."
    ),
    "properties": {
        "app": {"type": "string"},
        "text": {"type": "string"},
        "x": {"type": "number"},
        "y": {"type": "number"},
        "w": {"type": "number"},
        "h": {"type": "number"},
    },
}
SECONDS = {"type": "number", "description": "How long it stays up; it always ends on its own."}
STYLE = {
    "type": "string",
    "enum": ["box", "underline", "bracket", "ripple", "click"],
    "description": (
        "How the target is marked: box (default) round it; underline under a line of text; bracket, corner "
        "brackets that leave text readable; ripple, rings spreading from a small icon three times; click, a "
        "pointer shape where to click."
    ),
}

TOOLS = [
    {
        "name": "guide_status",
        "description": (
            "What is on the owner's screen now: screens, the frontmost app, the top windows with their frames, "
            "the curtain's end time, overlays still up, and recent events (answered, dismissed, left a "
            "spotlight, muted). Call it before pointing at anything, and after, to see what the owner did."
        ),
        "inputSchema": {"type": "object", "properties": {}},
        "cmd": "status",
    },
    {
        "name": "guide_spotlight",
        "description": (
            "Dim everything except one app's windows, to keep the owner on it. Switching to another app ends "
            "it (reported as a 'left' event): the owner can always look elsewhere."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "app": {"type": "string", "description": "App name as in guide_status, e.g. Safari"},
                "dim": {"type": "number", "description": "0.3 (faint) to 0.97 (near black); default 0.85"},
                "message": {"type": "string", "description": "Optional line shown at the top"},
                "seconds": dict(SECONDS, description="Default 300, at most 1800"),
            },
            "required": ["app"],
        },
        "cmd": "spotlight",
    },
    {
        "name": "guide_arrow",
        "description": (
            "Draw a pulsing arrow pointing at a target, with an optional label, to move the owner's eye. For an app "
            "target the reply says in_front; when false the target may be covered, so bring it forward first "
            "(guide_spotlight does)."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {"target": TARGET, "label": {"type": "string"}, "style": STYLE, "seconds": SECONDS},
            "required": ["target"],
        },
        "cmd": "arrow",
    },
    {
        "name": "guide_highlight",
        "description": "Mark a target with a pulsing frame (or another style), with an optional label.",
        "inputSchema": {
            "type": "object",
            "properties": {"target": TARGET, "label": {"type": "string"}, "style": STYLE, "seconds": SECONDS},
            "required": ["target"],
        },
        "cmd": "highlight",
    },
    {
        "name": "guide_focus",
        "description": (
            "Dim every screen except a lit circle that follows the mouse pointer and the target, with a line "
            "from the pointer to the target. Use it when the target is far from where the owner is looking. "
            "It lifts by itself when the owner brings the pointer onto the target (a 'reached' event in "
            "guide_status). An app target is brought forward and followed; the reply says in_front."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "target": TARGET,
                "label": {"type": "string"},
                "dim": {"type": "number", "description": "0.3 (faint) to 0.97 (near black); default 0.7"},
                "radius": {
                    "type": "number",
                    "description": "Lit circle round the pointer, 60 to 400 points; default 140",
                },
                "trail": {"type": "boolean", "description": "Draw the line from the pointer; default true"},
                "seconds": dict(SECONDS, description="Default 30, at most 300"),
            },
            "required": ["target"],
        },
        "cmd": "focus",
    },
    {
        "name": "guide_steps",
        "description": (
            "Number up to 5 targets as a sequence: the current step is outlined, pulses and shows its label; "
            "done steps show a grey tick, later ones are faint. Call it again with the next current to move on "
            "(it replaces the old one); current one past the last marks all done. At most one step may use "
            "{app, text}."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "steps": {
                    "type": "array",
                    "minItems": 1,
                    "maxItems": 5,
                    "items": {
                        "type": "object",
                        "properties": {"target": TARGET, "label": {"type": "string"}},
                        "required": ["target"],
                    },
                },
                "current": {"type": "integer", "description": "1-based step being done now; default 1"},
                "seconds": dict(SECONDS, description="Default 120, at most 600"),
            },
            "required": ["steps"],
        },
        "cmd": "steps",
    },
    {
        "name": "guide_message",
        "description": "Show a message card; a click closes it. position: center, top, bottom, or near a target.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "text": {"type": "string"},
                "position": {"type": "string", "enum": ["center", "top", "bottom", "near"]},
                "target": TARGET,
                "seconds": SECONDS,
            },
            "required": ["text"],
        },
        "cmd": "message",
    },
    {
        "name": "guide_ask",
        "description": (
            "Ask the owner a question with 2 to 4 buttons and wait for the click. Returns the chosen text, or "
            "says they closed it or did not answer in time. Keep choices short and put the one you recommend first."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "text": {"type": "string"},
                "choices": {"type": "array", "items": {"type": "string"}, "minItems": 2, "maxItems": 4},
                "position": {"type": "string", "enum": ["center", "top", "bottom", "near"]},
                "target": TARGET,
                "seconds": dict(SECONDS, description="How long to wait; default 120, at most 600"),
            },
            "required": ["text", "choices"],
        },
        "cmd": "ask",
    },
    {
        "name": "guide_clear",
        "description": "Remove one overlay by id, or all of them.",
        "inputSchema": {"type": "object", "properties": {"id": {"type": "string"}}},
        "cmd": "clear",
    },
    {
        "name": "guide_curtain",
        "description": (
            "Bring the dark curtain down sooner: in minutes (0 = now) or at HH:MM, within 14 hours, and only "
            "earlier than the end already set. Refused while the curtain is up, just after the owner lifted it, "
            "or while they paused it. It cannot lift, remove or postpone the curtain: only the owner can."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "minutes": {"type": "number"},
                "at": {"type": "string", "description": "HH:MM on the owner's clock"},
                "reason": {"type": "string", "description": "Written to the curtain's log"},
            },
        },
        "cmd": "curtain",
    },
]
BY_NAME = {t["name"]: t for t in TOOLS}


class GuideError(Exception):
    pass


def call(cmd, args):
    try:
        with open(ENDPOINT, encoding="utf-8") as f:
            port, token = f.read().split()[:2]
    except (OSError, ValueError):
        raise GuideError("Guide is not running on this Mac (start the Guide spoon in Hammerspoon)") from None
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/v1",
        data=json.dumps({"cmd": cmd, "args": args}).encode(),
        headers={"Content-Type": "application/json", "X-Guide-Token": token},
        method="POST",
    )
    # No proxy: an HTTP(S)_PROXY in the environment must never see the token.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(req, timeout=HTTP_TIMEOUT) as r:
            res = json.loads(r.read() or b"{}")
    except ValueError:
        raise GuideError("Guide answered something that is not JSON") from None
    except urllib.error.HTTPError as e:
        try:
            body = json.loads(e.read())
        except ValueError:
            body = None
        why = body.get("error") if isinstance(body, dict) else None
        raise GuideError(why or f"Guide answered {e.code}") from None
    except (urllib.error.URLError, OSError):
        raise GuideError("Guide is not answering (is Hammerspoon running?)") from None
    if not isinstance(res, dict):
        raise GuideError("Guide answered something that is not an object")
    return res


def ask(args):
    qid = call("ask", args)["id"]
    deadline = time.monotonic() + float(args.get("seconds") or 120) + 2
    while time.monotonic() < deadline:
        a = call("answer", {"id": qid})
        if not a.get("pending"):
            if a.get("answer") is not None:
                return {"id": qid, "answer": a["answer"]}
            return {"id": qid, "answer": None, "ended": a.get("ended") or "closed"}
        time.sleep(POLL_SECONDS)
    call("clear", {"id": qid})
    return {"id": qid, "answer": None, "ended": "expired"}


def run_tool(name, args):
    tool = BY_NAME.get(name)
    if tool is None:
        return {"content": [{"type": "text", "text": "unknown tool " + name}], "isError": True}
    try:
        res = ask(args) if tool["cmd"] == "ask" else call(tool["cmd"], args)
    except GuideError as e:
        return {"content": [{"type": "text", "text": str(e)}], "isError": True}
    return {"content": [{"type": "text", "text": json.dumps(res, ensure_ascii=False)}]}


def handle(msg):
    method, mid = msg.get("method"), msg.get("id")
    if mid is None:
        return None
    if method == "initialize":
        asked = (msg.get("params") or {}).get("protocolVersion")
        result = {
            "protocolVersion": asked if asked in PROTOCOLS else PROTOCOLS[0],
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "guide", "version": "1.0"},
        }
    elif method == "ping":
        result = {}
    elif method == "tools/list":
        result = {"tools": [{k: v for k, v in t.items() if k != "cmd"} for t in TOOLS]}
    elif method == "tools/call":
        p = msg.get("params")
        p = p if isinstance(p, dict) else {}
        args = p.get("arguments")
        result = run_tool(str(p.get("name", "")), args if isinstance(args, dict) else {})
    else:
        return {"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "unknown method " + str(method)}}
    return {"jsonrpc": "2.0", "id": mid, "result": result}


def main():
    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            out = {"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "parse error"}}
        else:
            out = handle(msg) if isinstance(msg, dict) else None
        if out is not None:
            sys.stdout.write(json.dumps(out, ensure_ascii=False) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
