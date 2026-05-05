#!/usr/bin/env python3
"""Tiny Foglet external-door example that reads safe context/env metadata."""

import json
import os
import sys


def load_context():
    path = os.environ.get("FOGLET_DOOR_CONTEXT", "")
    if not path:
        return {}
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def main():
    context = load_context()
    handle = context.get("handle") or os.environ.get("FOGLET_USERNAME") or "guest"
    width = context.get("terminal_width") or os.environ.get("FOGLET_TERMINAL_WIDTH") or "80"
    height = context.get("terminal_height") or os.environ.get("FOGLET_TERMINAL_HEIGHT") or "24"

    print(f"python-context-demo:{handle}:{width}x{height}", flush=True)
    print("Type /quit to return to Foglet.", flush=True)

    for line in sys.stdin:
        text = line.strip()
        if text == "/quit":
            print("Leaving Python Context Demo.", flush=True)
            return 0
        print(f"python> {text}", flush=True)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
