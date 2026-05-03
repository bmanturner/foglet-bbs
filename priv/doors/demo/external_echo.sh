#!/bin/sh
# Tiny non-Elixir external door used by FOG-516 runner tests and SSH harness QA.
# It receives only the allowlisted Foglet metadata that the runner exposes.

printf '%s:%s:%s\n' "$FOGLET_DOOR_ID" "$FOGLET_USERNAME" "$FOGLET_TERMINAL_WIDTH"
