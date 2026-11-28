"""guide_mcp.py run as a real stdio process against a stand-in for the Guide spoon's HTTP side.

Run from the repo root: python3 -m unittest test/guide_mcp_test.py (test/guide.bats does).
"""

import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import ClassVar

SERVER = os.path.join(os.path.dirname(__file__), "..", "hammerspoon", "Spoons", "Guide.spoon", "guide_mcp.py")
TOKEN = "t0ken"


class Spoon(BaseHTTPRequestHandler):
    """Answers like the spoon: checks the token, records each command, answers ask after two polls."""

    seen: ClassVar[list] = []
    polls = 0

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        Spoon.seen.append((self.headers.get("X-Guide-Token"), body["cmd"], body.get("args")))
        if self.headers.get("X-Guide-Token") != TOKEN:
            return self.reply(401, {"error": "bad token"})
        cmd = body["cmd"]
        if cmd == "ask":
            return self.reply(200, {"id": "ask-1"})
        if cmd == "answer":
            Spoon.polls += 1
            return self.reply(200, {"pending": True} if Spoon.polls < 3 else {"pending": False, "answer": "今やる"})
        if cmd == "curtain":
            return self.reply(409, {"error": "the curtain is up; the owner decides when it goes"})
        return self.reply(200, {"id": cmd + "-1"})

    def reply(self, code, obj):
        data = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *_):
        pass


class GuideMcpTest(unittest.TestCase):
    def setUp(self):
        Spoon.seen, Spoon.polls = [], 0
        self.http = HTTPServer(("127.0.0.1", 0), Spoon)
        threading.Thread(target=self.http.serve_forever, daemon=True).start()
        self.dir = tempfile.TemporaryDirectory()
        self.endpoint = os.path.join(self.dir.name, "endpoint")
        with open(self.endpoint, "w") as f:
            f.write(f"{self.http.server_port}\n{TOKEN}\n")

    def tearDown(self):
        self.http.shutdown()
        self.http.server_close()
        self.dir.cleanup()

    def session(self, *messages):
        # A proxy that goes nowhere: the call must not use it.
        dead = "http://127.0.0.1:9"
        env = dict(os.environ, GUIDE_ENDPOINT=self.endpoint, HTTP_PROXY=dead, http_proxy=dead, NO_PROXY="", no_proxy="")
        lines = "".join(json.dumps(m) + "\n" for m in messages)
        out = subprocess.run([sys.executable, SERVER], input=lines, capture_output=True, text=True,
                             env=env, check=False, timeout=10)
        self.assertEqual(out.stderr, "")
        return [json.loads(line) for line in out.stdout.splitlines()]

    def tool(self, name, args):
        return self.session({"jsonrpc": "2.0", "id": 1, "method": "tools/call",
                             "params": {"name": name, "arguments": args}})[0]["result"]

    def test_initialize_answers_the_clients_revision(self):
        r = self.session({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                          "params": {"protocolVersion": "2025-03-26"}},
                         {"jsonrpc": "2.0", "method": "notifications/initialized"})
        self.assertEqual(len(r), 1, "a notification gets no reply")
        self.assertEqual(r[0]["result"]["protocolVersion"], "2025-03-26")
        self.assertIn("tools", r[0]["result"]["capabilities"])

    def test_tools_list_has_no_way_to_lift_the_curtain(self):
        tools = self.session({"jsonrpc": "2.0", "id": 1, "method": "tools/list"})[0]["result"]["tools"]
        names = {t["name"] for t in tools}
        self.assertEqual(names, {"guide_status", "guide_spotlight", "guide_arrow", "guide_highlight",
                                 "guide_message", "guide_ask", "guide_clear", "guide_curtain", "guide_focus",
                                 "guide_steps"})
        for t in tools:
            self.assertNotIn("cmd", t)
            self.assertEqual(t["inputSchema"]["type"], "object")

    def test_call_sends_the_token_and_the_command_past_a_proxy(self):
        r = self.tool("guide_arrow", {"target": {"app": "Mail", "text": "送信"}, "label": "ここ"})
        self.assertNotIn("isError", r)
        self.assertEqual(Spoon.seen, [(TOKEN, "arrow", {"target": {"app": "Mail", "text": "送信"}, "label": "ここ"})])

    def test_focus_and_steps_reach_their_own_commands(self):
        steps = {"steps": [{"target": {"x": 1, "y": 2}, "label": "a"}], "current": 1}
        self.tool("guide_focus", {"target": {"x": 1, "y": 2}})
        self.tool("guide_steps", steps)
        self.assertEqual([c for _, c, _ in Spoon.seen], ["focus", "steps"])
        self.assertEqual(Spoon.seen[1][2], steps)

    def test_the_styles_offered_are_the_ones_the_spoon_takes(self):
        logic = os.path.join(os.path.dirname(SERVER), "logic.lua")
        with open(logic, encoding="utf-8") as f:
            line = next(x for x in f if x.startswith("M.STYLES"))
        spoon = set(re.findall(r"(\w+) = true", line))
        tools = self.session({"jsonrpc": "2.0", "id": 1, "method": "tools/list"})[0]["result"]["tools"]
        for t in tools:
            style = t["inputSchema"]["properties"].get("style")
            if style:
                self.assertEqual(set(style["enum"]), spoon, t["name"])

    def test_ask_waits_for_the_click(self):
        r = self.tool("guide_ask", {"text": "どうする?", "choices": ["今やる", "あとで"]})
        self.assertEqual(json.loads(r["content"][0]["text"]), {"id": "ask-1", "answer": "今やる"})
        self.assertEqual(Spoon.polls, 3)

    def test_a_refusal_reaches_the_ai_as_an_error(self):
        r = self.tool("guide_curtain", {"minutes": 5})
        self.assertTrue(r["isError"])
        self.assertIn("owner decides", r["content"][0]["text"])

    def test_not_running(self):
        os.remove(self.endpoint)
        r = self.tool("guide_status", {})
        self.assertTrue(r["isError"])
        self.assertIn("not running", r["content"][0]["text"])
        self.assertEqual(Spoon.seen, [])

    def test_odd_params_do_not_end_the_server(self):
        r = self.session({"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": []},
                         {"jsonrpc": "2.0", "id": 2, "method": "ping"})
        self.assertTrue(r[0]["result"]["isError"])
        self.assertEqual(r[1]["result"], {})

    def test_unknown_method(self):
        r = self.session({"jsonrpc": "2.0", "id": 7, "method": "resources/list"})
        self.assertEqual(r[0]["error"]["code"], -32601)


if __name__ == "__main__":
    unittest.main()
