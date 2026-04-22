---
phase: 260422-omm-today-handle-ssh-msg-for-pty-data-window
reviewed: 2026-04-22T23:12:25Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - lib/foglet_bbs/ssh/cli_handler.ex
  - test/foglet_bbs/ssh/cli_handler_test.exs
findings:
  critical: 0
  warning: 0
  info: 0
  total: 0
status: resolved
---

# Phase 260422-omm: Code Review Report

**Reviewed:** 2026-04-22T23:12:25Z
**Depth:** standard
**Files Reviewed:** 2
**Status:** resolved

## Summary

Reviewed the SSH CLIHandler production changes and the new real/direct callback coverage for PTY, shell, data, resize, EOF, closed, CRLF normalization, alt-screen restore, and lifecycle EXIT handling. No critical or blocking issues were found. One cleanup gap was found in the lifecycle EXIT path and has been resolved.

## Warnings

### WR-01: Lifecycle EXIT path leaks active SSH connection count - resolved

**File:** `lib/foglet_bbs/ssh/cli_handler.ex:147`

**Issue:** `handle_msg({:EXIT, lifecycle_pid, reason}, state)` sends the alt-screen LEAVE escape, closes the SSH channel, and returns `{:stop, ...}` directly. The active connection counter is only decremented in the `{:closed, ...}` callback at lines 232-245, and `terminate/2` only stops lifecycle/session processes. If the lifecycle exits first, which is the intended graceful quit path described in the comments, the handler can stop before processing `:closed`, leaving `Foglet.SSH.CLIHandler.Counter` artificially high. Over time, normal user quits can exhaust the 500-connection limit and cause valid future connections to be rejected.

**Fix:** Perform the same active-connection cleanup in the matching lifecycle EXIT path, or factor it into a shared helper used by both `:closed` and lifecycle EXIT. Add a regression test that seeds the counter to `1`, invokes `handle_msg({:EXIT, lifecycle_pid, :shutdown}, state)` with a real `channel_id`, and asserts the ETS counter returns to `0`.

```elixir
def handle_msg({:EXIT, pid, reason}, %{lifecycle_pid: pid} = state) do
  Logger.info(
    "[SSH.CLIHandler] Lifecycle #{inspect(pid)} exited (#{inspect(reason)}); closing channel"
  )

  send_alt_screen_leave(state)
  maybe_close_channel(state)

  unless state.over_limit do
    _ = decrement_connection_count()
  end

  {:stop, state.channel_id || 0, state}
end
```

**Resolution:** Fixed in commit `e123787`. The lifecycle EXIT path now decrements the active connection counter when the connection was not rejected as over-limit, and the matching direct callback test seeds the counter to `1` and asserts it returns to `0`.

---

_Reviewed: 2026-04-22T23:12:25Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
