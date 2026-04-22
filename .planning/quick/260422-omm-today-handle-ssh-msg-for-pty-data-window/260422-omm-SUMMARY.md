---
status: complete
quick_id: 260422-omm
date: 2026-04-22
commit: 4dfc670
---

# Quick Task 260422-omm Summary

## Completed

- Added real in-process Erlang `:ssh.daemon` + `:ssh.connect` coverage for `Foglet.SSH.CLIHandler` PTY allocation, shell startup, CRLF-normalized output, and EOF alternate-screen LEAVE bytes.
- Added deterministic direct callback tests for `:data`, `:window_change`, `:closed`, matching lifecycle `{:EXIT, ...}`, and non-matching lifecycle exits.
- Converted `CLIHandlerTest` to `async: false` and added test helpers for temporary host keys, daemon startup on port `0`, raw channel byte collection, and fake Lifecycle dispatcher lookup.
- Fixed the production request-reply defect exposed by the real SSH harness: successful PTY and shell requests now call `:ssh_connection.reply_request/4`.
- Fixed the code-review warning that matching lifecycle `{:EXIT, ...}` could bypass the active connection-counter decrement.

## Deviations

- Production code was changed because the real SSH harness exposed the expected missing `want_reply` defect: `:ssh_connection.ptty_alloc/4` timed out until `CLIHandler` replied to successful PTY requests.

## Verification

- `mix test test/foglet_bbs/ssh/cli_handler_test.exs` passed: 16 tests, 0 failures.
- `mix precommit` passed.
- Code review warning WR-01 resolved in `e123787`.

## Code Commit

- `4dfc670` - `fix(quick-260422-omm): cover SSH CLI channel events`
- `e123787` - `fix(quick-260422-omm): close lifecycle exit counter leak`
