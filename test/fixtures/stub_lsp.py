#!/usr/bin/env python3
"""A language server that does nothing except be a language server.

Enough of LSP for a real Neovim client to spawn it, complete the initialize
handshake and stay attached: that is all ci_nvim_loading_test.sh needs to
assert "opening a .ts file attaches a client". Installing a real server
(mason/npm) in CI would test npm, not this config, and the e2e run
deliberately sets DOTFILES_NO_NVIM_AUTO_INSTALL to keep startups
deterministic.

The test drops a wrapper named `typescript-language-server` earlier on PATH
than anything else, so nvim resolves lspconfig's real `ts_ls` cmd to this.
"""

import json
import sys


def read_message():
    """Read one Content-Length framed JSON-RPC message, or None at EOF."""
    headers = {}
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            return None
        line = line.strip()
        if not line:
            break
        key, _, value = line.decode('ascii', 'replace').partition(':')
        headers[key.strip().lower()] = value.strip()
    length = int(headers.get('content-length', 0))
    if not length:
        return None
    return json.loads(sys.stdin.buffer.read(length))


def send(payload):
    data = json.dumps(payload).encode('utf-8')
    sys.stdout.buffer.write(b'Content-Length: %d\r\n\r\n' % len(data))
    sys.stdout.buffer.write(data)
    sys.stdout.buffer.flush()


def main():
    while True:
        message = read_message()
        if message is None:
            return
        method = message.get('method')
        if method == 'exit':
            return
        if 'id' not in message:
            # A notification (initialized, didOpen, ...): nothing to answer.
            continue
        if method == 'initialize':
            send({
                'jsonrpc': '2.0',
                'id': message['id'],
                'result': {
                    'capabilities': {'textDocumentSync': 1},
                    'serverInfo': {'name': 'stub-lsp'},
                },
            })
        else:
            # Every other request (shutdown included) gets a null result.
            send({'jsonrpc': '2.0', 'id': message['id'], 'result': None})


if __name__ == '__main__':
    main()
