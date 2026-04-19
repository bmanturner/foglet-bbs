---
phase: 03-ssh-server-tui
fixed_at: 2026-04-19T00:00:00Z
review_path: .planning/phases/03-ssh-server-tui/03-REVIEW.md
iteration: 1
findings_in_scope: 9
fixed: 8
skipped: 1
status: partial
---

# Phase 03: Code Review Fix Report

**Fixed at:** 2026-04-19
**Source review:** .planning/phases/03-ssh-server-tui/03-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 9
- Fixed: 8
- Skipped: 1 (WR-02 covered by CR-01 fix)

## Fixed Issues

### CR-01: Connection counter decremented twice per normal disconnect

**Files modified:** `lib/foglet_bbs/ssh/cli_handler.ex`
**Commit:** 785b9e5
**Applied fix:** Removed teardown and decrement from the `:eof` handler body — it now returns `{:ok, state}` with a comment explaining the protocol sequence. All cleanup (stop_lifecycle, stop_session, decrement_connection_count) remains only in the `:closed` handler.

---

### CR-02: Race condition in `:persistent_term` connection counter

**Files modified:** `lib/foglet_bbs/ssh/cli_handler.ex`, `lib/foglet_bbs/ssh/supervisor.ex`
**Commit:** b276c81
**Applied fix:** Replaced the non-atomic `:persistent_term` read-modify-write with an ETS named table (`Foglet.SSH.CLIHandler.Counter`). `check_connection_limit/0` now uses `:ets.update_counter/3` for an atomic increment, then decrements and returns `:over_limit` if the ceiling was exceeded. `decrement_connection_count/0` uses the same atomic op with a floor of 0. `init_counter/0` (public) is called once from `Foglet.SSH.Supervisor.init/1` before the daemon starts. The old `increment_connection_count/0` becomes a no-op since the check already increments atomically.

---

### CR-03: `{:terminate_after_modal, :pending_approval}` silently dropped

**Files modified:** `lib/foglet_bbs/tui/app.ex`
**Commit:** 77d3942
**Applied fix:** Added a `do_update({:terminate_after_modal, _reason}, state)` clause before the catch-all. It patches the existing modal's `on_confirm` and `on_cancel` callbacks to issue `Command.quit()`, ensuring the session terminates after the user dismisses the pending-approval notice regardless of which key they press. A fallback modal is synthesised if state.modal is somehow nil.

---

### WR-01: `PostReader` navigates to `:post_composer` without calling `PostComposer.init_screen_state/1`

**Files modified:** `lib/foglet_bbs/tui/screens/post_reader.ex`
**Commit:** 28aa39b
**Applied fix:** Replaced the bare `%{mode: :edit, reply_to: reply_to, error: nil}` map with an explicit call to `Foglet.TUI.Screens.PostComposer.init_screen_state(reply_to: reply_to, width: w)`, where `w` is extracted from `state.terminal_size`. This guarantees the `input_state` key is always present before the composer renders.

---

### WR-03: `verify.ex` resend key bypasses cooldown

**Files modified:** `lib/foglet_bbs/tui/screens/verify.ex`
**Commit:** b8744c6
**Applied fix:** Added a `cooldown?/1` check at the top of `resend_code/1`. When the user is in cooldown and presses R/r, the cooldown modal is shown instead of calling `resend_code_raw/1`. This is consistent with the typed-character handler behaviour.

---

### IN-01: `drop_last_grapheme/1` in `login.ex` is unnecessarily O(n)

**Files modified:** `lib/foglet_bbs/tui/screens/login.ex`
**Commit:** 9786b25
**Applied fix:** Replaced the four-pass grapheme/take/join implementation with the two-pass `String.slice(str, 0, String.length(str) - 1)` form, matching the convention used in `register.ex`.

---

### IN-02: `format_notification/2` exposes raw `inspect/1` output to users

**Files modified:** `lib/foglet_bbs/tui/app.ex`, `test/foglet_bbs/tui/app_test.exs`
**Commit:** e27b1c1
**Applied fix:** Replaced the single `case kind do` function with three function-head clauses: one for `:dm` matching `%{body: body}`, one for `:mention` matching `%{thread_title: t}`, and a safe catch-all returning `"Notification: #{kind}"`. The existing test was updated to pass a well-formed `%{body: "hey!"}` payload instead of a plain string, so the `:dm` clause fires and the `=~ "message"` assertion still holds.

---

### IN-03: `app_test.exs` omits `:new_thread` from view smoke test

**Files modified:** `test/foglet_bbs/tui/app_test.exs`
**Commit:** 86d82f1
**Applied fix:** Added `:new_thread` to the screen list in the "renders without crashing for every current_screen value" test.

---

## Skipped Issues

### WR-02: `handle_ssh_msg {:eof}` returns `{:ok, state}` leaving channel open after client EOF

**File:** `lib/foglet_bbs/ssh/cli_handler.ex:179-184`
**Reason:** Covered by CR-01 fix (commit 785b9e5). The CR-01 fix removed all teardown from the `:eof` handler, leaving it as `{:ok, state}` — exactly the intended behaviour described in WR-02's own fix note: "By removing teardown from `:eof`, the channel stays open briefly and awaits the forthcoming `:closed`. This is the standard SSH protocol sequence."
**Original issue:** `:eof` handler was calling teardown and returning `{:ok, state}`, keeping the channel open with a terminated lifecycle.

---

_Fixed: 2026-04-19_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
