#!/usr/bin/env bash
# PostToolUse hook: run `mix format` on Elixir files after Edit/Write/MultiEdit.
# Reads the hook JSON payload from stdin and extracts tool_input.file_path.
set -euo pipefail

payload="$(cat)"
file="$(printf '%s' "$payload" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"

[ -z "${file:-}" ] && exit 0

case "$file" in
  *.ex|*.exs|*.heex) ;;
  *) exit 0 ;;
esac

[ -f "$file" ] || exit 0

cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"
rtk mix format "$file" >/dev/null 2>&1 || true
exit 0
