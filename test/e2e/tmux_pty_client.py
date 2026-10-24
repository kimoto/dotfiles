"""Attach a tmux client in a pty and play its terminal's focus reports.

Usage: tmux_pty_client.py <socket> <session> <cols> <rows>
Reads commands from stdin, one per line: `in` / `out` send the focus-in /
focus-out report a terminal like Ghostty sends with focus-events on; EOF
detaches. A pty rather than script(1): BSD script refuses a stdin that is not
a terminal, and this has to run on macOS as well as in CI.
"""
import fcntl
import os
import pty
import select
import struct
import sys
import termios

REPORTS = {"in": b"\x1b[I", "out": b"\x1b[O"}


def main():
    sock, session, cols, rows = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
    env = {k: v for k, v in os.environ.items() if k != "TMUX"}
    env["TERM"] = "xterm-256color"
    pid, fd = pty.fork()
    if pid == 0:
        os.execvpe("tmux", ["tmux", "-L", sock, "attach", "-t", session], env)
    # The session's own size: a 0x0 client would shrink the window and wrap
    # the lines the test greps for.
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    stdin = sys.stdin.fileno()
    watching = [fd, stdin]
    while watching:
        ready, _, _ = select.select(watching, [], [])
        if fd in ready:
            # Drain the client's output so a full pty buffer never stalls it.
            try:
                if not os.read(fd, 65536):
                    return
            except OSError:
                return
        if stdin in ready:
            line = os.read(stdin, 1024)
            if not line:
                watching.remove(stdin)
                os.kill(pid, 15)
                continue
            for word in line.decode().split():
                os.write(fd, REPORTS[word])


if __name__ == "__main__":
    main()
