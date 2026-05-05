#!/usr/bin/env python3
"""Minimal full-screen external door probe for PTY adapter tests."""

import fcntl
import os
import signal
import struct
import sys
import termios


def size():
    try:
        rows, cols, _, _ = struct.unpack("HHHH", fcntl.ioctl(0, termios.TIOCGWINSZ, struct.pack("HHHH", 0, 0, 0, 0)))
        return cols, rows
    except OSError:
        return 0, 0


def write(text):
    # SIGWINCH can arrive while the probe is producing startup or prompt output.
    # Use unbuffered writes so the signal handler cannot re-enter Python's
    # buffered stdout object and crash with `RuntimeError: reentrant call`.
    os.write(1, text.encode("utf-8", "replace"))


def on_winch(_signum, _frame):
    cols, rows = size()
    write(f"resize:{cols}x{rows}\r\n")


signal.signal(signal.SIGWINCH, on_winch)
cols, rows = size()
write("\x1b[?1049h\x1b[2J\x1b[H")
write(f"fullscreen-probe:{cols}x{rows}\r\n")
write("type /quit to leave\r\n")

for line in sys.stdin:
    line = line.rstrip("\r\n")
    if line in ("", "/quit"):
        write("leaving-fullscreen\r\n")
        write("\x1b[?1049l")
        raise SystemExit(0)
    write(f"probe> {line}\r\n")

write("\x1b[?1049l")
