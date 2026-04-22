---
status: passed
quick_id: 260422-omm
date: 2026-04-22
commit: 4dfc670
---

# Quick Task 260422-omm Verification

## Must-Haves

- PASS: Real SSH daemon/client tests exercise PTY allocation and shell startup through `Foglet.SSH.CLIHandler`.
- PASS: Raw SSH channel output asserts alternate-screen ENTER (`\e[?1049h`) on startup.
- PASS: Raw SSH channel output asserts CRLF-normalized terminal bytes and rejects bare LF.
- PASS: Raw SSH channel output asserts alternate-screen LEAVE (`\e[?1049l`) after client EOF.
- PASS: Direct callback tests cover `:data`, `:window_change`, `:closed`, matching lifecycle `{:EXIT, ...}`, and non-matching lifecycle exits.
- PASS: `:window_change` assertions include returned state, resize dispatch, and guest session `terminal_size` update.
- PASS: `:closed` assertions include guest session cleanup via monitor `:DOWN`.
- PASS: Production changes are limited to PTY/shell `:ssh_connection.reply_request/4` success replies.

## Evidence

- Added `real SSH channel startup` tests in `test/foglet_bbs/ssh/cli_handler_test.exs`.
- Added `direct SSH callbacks` tests in `test/foglet_bbs/ssh/cli_handler_test.exs`.
- Updated `lib/foglet_bbs/ssh/cli_handler.ex` to reply to successful PTY and shell requests.
- `mix test test/foglet_bbs/ssh/cli_handler_test.exs` completed with 16 tests and 0 failures.
- `mix precommit` completed successfully.

## Result

Verified.
