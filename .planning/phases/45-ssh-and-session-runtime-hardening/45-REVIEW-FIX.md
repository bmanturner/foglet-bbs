---
phase: 45-ssh-and-session-runtime-hardening
fixed_at: 2026-04-29T20:20:00Z
review_path: .planning/phases/45-ssh-and-session-runtime-hardening/45-REVIEW.md
iteration: 1
findings_in_scope: 9
fixed: 9
skipped: 0
status: all_fixed
---

# Phase 45: Code Review Fix Report

**Fixed at:** 2026-04-29T20:20:00Z
**Source review:** .planning/phases/45-ssh-and-session-runtime-hardening/45-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 9 (5 Warning + 4 Info; fix scope = `all`)
- Fixed: 9
- Skipped: 0

All findings were applied as 7 atomic commits. Two pairs were grouped for
cohesion: WR-02+WR-03 (both harden the supervisor's timeout-fallback path,
sharing the same call site) and WR-04+IN-03 (both touch `App.do_update({:promote_session, …}, …)`).

The Phase 45 sessions + SSH test suite (78 tests across
`test/foglet_bbs/sessions/` and `test/foglet_bbs/ssh/`) is green after every
fix. Six pre-existing failures in `test/foglet_bbs/tui/app_test.exs` are
unrelated to this phase — they reference `Foglet.TUI.AppTest.FakePosts.list_reader_window/2`,
which was introduced in Phase 44-02 and was already failing on `main` before
this fix run.

## Fixed Issues

### WR-01: `Session.promote_to_user` mutates state even when Registry registration fails

**Files modified:** `lib/foglet_bbs/sessions/session.ex`
**Commit:** f4d261a4
**Applied fix:** Reorder the cast handler so `Registry.register/3` runs first
and gates the identity merge. On `{:error, {:already_registered, other_pid}}`
the session now stops with `{:registry_collision, user.id}` instead of
silently merging `user_id`/`handle`/`role`/preferences into an unregistered
process. The `Logger.info("Session guest promoted", …)` event moved into the
`:ok` branch so a refused promote doesn't emit a misleading success log.

### WR-02: `Supervisor.replace/2` timeout branch raises on `terminate_child` error

**Files modified:** `lib/foglet_bbs/sessions/supervisor.ex`
**Commit:** 3bf6aadd
**Applied fix:** Replaced the strict `:ok = DynamicSupervisor.terminate_child(__MODULE__, old_pid)`
match with a `case … do` that mirrors `replace_then_promote/4`: on `{:error, reason}`
log a warning and `Process.exit(old_pid, :kill)` so a benign timing race on
the old session's exit no longer crashes the calling CLIHandler and drops the
new connection.

### WR-03: `replace_then_promote` timeout-fallback path can land on a still-registered Registry slot

**Files modified:** `lib/foglet_bbs/sessions/supervisor.ex`
**Commit:** 3bf6aadd
**Applied fix:** After the timeout-branch terminate/kill, drain the Registry's
own mailbox via `:sys.get_state(@registry)` so its monitor on `old_pid` is
processed and the `user.id` slot is cleared before the guest's
`Registry.register/3` runs. This is the same idiom already used in
`supervisor_test.exs:56`. Combined with WR-01's hard refusal on a still-held
slot, the system can no longer enter the half-promoted-but-unregistered state
described in the review.

**Note:** Logic-level change — the fix relies on `:sys.get_state/1`
synchronously draining the Registry's mailbox. The supervisor test suite (28
tests) passes including the previously brittle force-terminates path. Worth a
human eye on the synchronization assumption before the verifier phase.

### WR-04: `App.do_update({:promote_session, user}, …)` does not update `session_context.user`

**Files modified:** `lib/foglet_bbs/tui/app.ex`
**Commit:** 7f31b5c6
**Applied fix:** Update `state.session_context` in lockstep with
`current_user`: `:user` and `:user_id` are written from the promoted user, and
`:pubkey_authenticated` is intentionally left unchanged (TUI-driven login is
password-based, not pubkey-based). Screens that read `session_context.user`
rather than `current_user` now see the authenticated identity immediately.

### WR-05: `get_dispatcher/1` synchronous call per input event

**Files modified:** `lib/foglet_bbs/ssh/cli_handler.ex`,
`test/foglet_bbs/ssh/cli_handler_test.exs`
**Commit:** 4f4942cc
**Applied fix:** Added `dispatcher_pid` to the `%CLIHandler{}` struct, resolved
once at PTY allocation immediately after `Lifecycle.start_link/2` via the
renamed `resolve_dispatcher/1` helper. `dispatch_events/2` now takes the
cached pid and is a pure cast loop with no synchronous boundary into the
Lifecycle. The unused `start_fake_lifecycle!/1` test helper was removed since
no test exercises the resolution path; the two callers were updated to seed
`dispatcher_pid: self()` directly on `%CLIHandler{}`.

### IN-01: Double-cast on terminal resize

**Files modified:** `lib/foglet_bbs/ssh/cli_handler.ex`,
`test/foglet_bbs/ssh/cli_handler_test.exs`
**Commit:** e2e7d49f
**Applied fix:** Removed the CLIHandler-side `Sessions.Session.set_terminal_size/2`
cast on `:window_change`. App now owns the "session knows its size" invariant
via `do_update({:window_change, …}, …)`, which is reached through the
already-dispatched `:window` event. The `:window_change` test was updated to
assert the resize+window event dispatch contract (no longer a direct session
cast).

### IN-02: `do_channel_up` over-limit branch discards incoming `state`

**Files modified:** `lib/foglet_bbs/ssh/cli_handler.ex`
**Commit:** 802351d1
**Applied fix:** Both rejection branches (over-limit and rate-limit) now use
`%__MODULE__{state | …}` update-syntax instead of constructing a fresh struct.
Symmetric with the accepted branch; future fields set in `init/1` will be
preserved on rejection paths.

### IN-03: `App.do_update({:promote_session, user}, …)` silently degrades when `session_pid` is nil

**Files modified:** `lib/foglet_bbs/tui/app.ex`
**Commit:** 7f31b5c6
**Applied fix:** Added an `else` branch with a `Logger.warning` that flags the
"logged in without Session" condition (no heartbeats, no terminal-size
updates, no replacement enforcement, no audit log). Production telemetry can
now surface the case. Bundled with WR-04 since both touch the same clause.

### IN-04: `PubkeyStash` legacy two-tuple entries can leak past sweep

**Files modified:** `lib/foglet_bbs/ssh/pubkey_stash.ex`
**Commit:** c02b1e4b
**Applied fix:** Extended `sweep/2`'s match spec with a second clause
`{{:"$1", :"$2"}, [], [true]}` that unconditionally deletes legacy two-tuple
entries. The moduledoc was updated to reflect the new behavior; the legacy
shape is documented as orphan-only by the time sweep runs.

---

_Fixed: 2026-04-29T20:20:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
