#!/usr/bin/env python3
"""Classic/dropfile-style Foglet demo door.

Reads whichever generated dropfile is present in the working directory and then
returns cleanly to Foglet when the user types /quit.
"""

from pathlib import Path
import sys


def first_existing_dropfile():
    for name in ("DOOR.SYS", "DORINFO.DEF", "CHAIN.TXT"):
        path = Path(name)
        if path.exists():
            return name, path.read_text(encoding="utf-8", errors="replace").splitlines()
    return None, []


def main():
    name, lines = first_existing_dropfile()
    handle = lines[36] if name == "DOOR.SYS" and len(lines) > 36 else None
    handle = handle or (lines[6] if name == "DORINFO.DEF" and len(lines) > 6 else None)
    handle = handle or (lines[0] if lines else "guest")

    print(f"classic-dropfile-demo:{name or 'none'}:{handle}", flush=True)
    print("Type /quit to return to Foglet.", flush=True)

    for line in sys.stdin:
        text = line.strip()
        if text in {"/quit", "q", "Q"}:
            print("Leaving Classic Dropfile Demo.", flush=True)
            return 0
        print(f"classic> {text}", flush=True)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
