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
    sys.stdout.write(text)
    sys.stdout.flush()


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
