# Phase 45: SSH And Session Runtime Hardening - Context

**Gathered:** 2026-04-30 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 45 hardens the SSH/session runtime paths operators depend on: public-key
offer correlation, guest-to-user promotion audit logs, SSH channel termination
cleanup, global connection counter balance, and the existing forced-promotion
fallback proof.

Locked requirements come from `45-SPEC.md`: `Foglet.SSH.PubkeyStash` must have
TTL-based sweep behavior for orphaned key offers; guest promotion logs must
carry structured metadata including user identity, session identity, peer
context when available, and replacement context when known; `Foglet.SSH.CLIHandler`
termination-sensitive callbacks must delegate full cleanup to one helper; the
connection counter must be proven balanced across normal close, EOF-to-close,
lifecycle exit, over-limit reject, rate-limit reject, and crash-during-init
paths; and the deterministic `replace_then_promote/3` forced fallback coverage
must remain in place or be replaced with equivalent proof.
</domain>

<decisions>
## Implementation Decisions

### Public-Key Stash Cleanup
- **D-01:** Add timestamped TTL/sweep behavior inside `Foglet.SSH.PubkeyStash`
  rather than introducing durable storage or changing the SSH authentication
  model. ETS remains ephemeral and reconstructable; stale entries are bounded
  by age and removed through an explicit sweep path.
- **D-02:** Keep `put/2` and `pop/1` semantics compatible for `KeyCB` and
  `CLIHandler`. Add the smallest public or test-supported API needed to make
  stale-entry cleanup deterministic, such as injectable timestamps, a sweep
  function, or TTL options.
- **D-03:** Do not change `no_auth_needed: true` or the guest fallback behavior.
  Public-key matching remains a convenience handoff into an authenticated
  session when the offered key matches; missing or expired stash entries still
  become guest sessions.

### Promotion Audit Metadata
- **D-04:** Carry peer metadata from `Foglet.SSH.CLIHandler` into the session
  context/promotion path instead of logging peer context only at channel-up
  time. Promotion happens later through `Foglet.TUI.App` and
  `Foglet.Sessions.Supervisor`, so the peer must be available at that boundary.
- **D-05:** Emit structured Logger metadata for guest-to-user promotion,
  including promoted session pid or identity, target user id/handle, peer
  context when available, and whether a prior session was replaced when known.
  Durable database audit rows are out of scope.
- **D-06:** Preserve one-session-per-user semantics. Any replacement metadata
  should describe the existing replacement protocol; it must not introduce a
  new replacement model or weaken the Registry-slot-before-promotion invariant.

### Unified CLIHandler Cleanup
- **D-07:** Extract one cleanup helper in `Foglet.SSH.CLIHandler` that owns
  alt-screen leave, lifecycle stop, session stop, connection-counter decrement,
  and channel close where applicable.
- **D-08:** Make cleanup idempotent enough for callback delegation: EOF may
  restore the alt screen while the actual stop follows on closed, lifecycle
  EXIT may close the channel before `terminate/2`, and `terminate/2` may run
  after partial cleanup. The shared helper should prevent double decrement
  and tolerate already-closed resources.
- **D-09:** Keep terminal restoration best-effort and direct to the SSH channel.
  The phase hardens existing cleanup paths; it should not redesign Raxol
  lifecycle ownership or terminal rendering behavior.

### Connection Counter Proof
- **D-10:** Prove counter balance with focused callback/unit paths plus the
  existing real SSH channel coverage where it provides useful confidence. Do
  not require brittle full-network simulations for every listed branch when a
  deterministic direct callback path can prove the invariant.
- **D-11:** Tests should reset the ETS counter explicitly, drive each listed
  lifecycle path, and assert the counter returns to the expected value without
  drifting upward or below zero.
- **D-12:** Over-limit reject and rate-limit reject paths should remain
  semantically rejected states that do not require later decrement. The tests
  should make this explicit so future cleanup refactors do not double-decrement
  or leak counts.

### Forced-Promotion Fallback
- **D-13:** Preserve the existing deterministic
  `promote_guest_session/2 force-terminates a session that does not stop
  gracefully` test as the SESS-01 acceptance proof unless implementation
  changes require an equivalent assertion.
- **D-14:** Keep the fallback proof process-synchronized with monitors and
  Registry/state checks. Avoid `Process.sleep/1` and pure liveness checks.

### the agent's Discretion
- Downstream agents may choose exact TTL duration, sweep function names,
  metadata key names, and whether promotion metadata is passed as opts or
  stored in `SessionContext`, provided the result is grep-friendly and tested.
- Downstream agents may choose whether cleanup idempotence is represented by
  state flags, returned state, helper options, or narrow callback-specific
  wrapper functions, provided counter behavior is provably balanced.
- Downstream agents may add test-only helpers when they make fragile SSH paths
  deterministic without broadening production APIs unnecessarily.

### Folded Todos
No matching todos were folded into this phase.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `.planning/phases/45-ssh-and-session-runtime-hardening/45-SPEC.md`
- `.planning/phases/44-postreader-and-content-query-hardening/44-CONTEXT.md`
- `.planning/phases/43-large-screen-decomposition/43-CONTEXT.md`
- `.planning/phases/42-app-runtime-helper-extraction/42-CONTEXT.md`
- `.planning/phases/41-tui-contract-and-modal-effects/41-CONTEXT.md`
- `.planning/ROADMAP.md`
- `.planning/REQUIREMENTS.md`
- `.planning/PROJECT.md`
- `.planning/codebase/CONCERNS.md`
- `.planning/codebase/ARCHITECTURE.md`
- `.planning/codebase/CONVENTIONS.md`
- `.planning/codebase/INTEGRATIONS.md`
- `.planning/codebase/TESTING.md`
- `lib/foglet_bbs/ssh/pubkey_stash.ex`
- `lib/foglet_bbs/ssh/key_cb.ex`
- `lib/foglet_bbs/ssh/cli_handler.ex`
- `lib/foglet_bbs/ssh/supervisor.ex`
- `lib/foglet_bbs/ssh/rate_limiter.ex`
- `lib/foglet_bbs/sessions/session.ex`
- `lib/foglet_bbs/sessions/supervisor.ex`
- `lib/foglet_bbs/tui/app.ex`
- `lib/foglet_bbs/tui/app/effects.ex`
- `lib/foglet_bbs/tui/session_context.ex`
- `test/foglet_bbs/ssh/cli_handler_test.exs`
- `test/foglet_bbs/ssh/key_cb_test.exs`
- `test/foglet_bbs/ssh/rate_limiter_test.exs`
- `test/foglet_bbs/ssh/supervisor_test.exs`
- `test/foglet_bbs/sessions/session_test.exs`
- `test/foglet_bbs/sessions/supervisor_test.exs`
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.SSH.PubkeyStash` already centralizes public-key offer storage in a
  named ETS table and exposes `init/0`, `put/2`, and destructive `pop/1`.
- `Foglet.SSH.KeyCB.is_auth_key/3` already extracts peer information from
  SSH callback opts and stashes the offered public key under that peer key.
- `Foglet.SSH.CLIHandler` already reads peer information at
  `:ssh_channel_up`, applies connection limit and rate limiting, pops the
  stash, starts a guest or authenticated session, owns alt-screen enter/leave,
  starts Raxol Lifecycle, handles SSH data/resize/eof/closed messages, and
  owns the ETS connection counter.
- `Foglet.TUI.SessionContext` is the typed context value passed from
  `CLIHandler` into `Foglet.TUI.App`; it is the natural place to carry SSH
  peer metadata to later TUI login promotion if downstream planning prefers
  context-carried metadata.
- `Foglet.TUI.App` already routes login success through
  `Foglet.Sessions.Supervisor.promote_guest_session/2`, preserving
  one-session-per-user replacement before navigating to `:main_menu`.
- `Foglet.Sessions.Supervisor` already owns replacement and
  `replace_then_promote/3`; `Foglet.Sessions.Session` owns the final
  `{:promote_to_user, user}` cast and current promotion log.

### Established Patterns
- SSH runtime state is process/ETS-owned and ephemeral; durable identity lives
  in Accounts/Postgres, not in the SSH layer.
- Tests use direct SSH callback invocations for deterministic behavior and
  real SSH daemon tests only where wire-level terminal behavior matters.
- Existing SSH tests reset `Foglet.SSH.CLIHandler.Counter` by deleting and
  reinitializing the ETS table before counter-sensitive assertions.
- Session tests use monitors, Registry lookups, `:sys.get_state/1`, and direct
  state assertions rather than sleeps or `Process.alive?/1`.
- Logger assertions elsewhere use `ExUnit.CaptureLog`; promotion audit tests
  can follow that pattern while asserting Logger metadata rather than matching
  only message text.

### Integration Points
- `PubkeyStash.put/2` currently stores `{peer_key, public_key}` with no
  timestamp; `pop/1` expects that exact tuple shape.
- `CLIHandler.resolve_pubkey_user/1` consumes `PubkeyStash.pop(peer)` and
  treats `:miss` as guest session startup.
- `CLIHandler.handle_ssh_msg({:eof, ...})`, `handle_ssh_msg({:closed, ...})`,
  `handle_msg({:EXIT, lifecycle_pid, reason}, ...)`, and `terminate/2`
  currently open-code overlapping cleanup.
- `CLIHandler.check_connection_limit/0` increments the ETS counter and
  immediately compensates on over-limit. Rate-limit rejection currently calls
  `decrement_connection_count/0` even though the comment says the counter was
  incremented inside `check_connection_limit/0`.
- `App.do_update({:promote_session, user}, state)` currently knows only
  `state.session_pid` and `user`, so peer/replacement audit metadata needs an
  explicit path into this call chain.
- `Session.handle_cast({:promote_to_user, user}, state)` currently logs user
  id and handle as interpolated message text before Registry registration.
</code_context>

<specifics>
## Specific Ideas

- Treat peer metadata as audit context, not authorization. It should improve
  observability without changing authentication outcomes.
- Prefer structured Logger metadata and `CaptureLog` assertions over durable
  audit tables, since the phase spec explicitly excludes database audit rows.
- Keep this phase bounded to SSH-01 through SSH-04 and SESS-01. Do not reopen
  browser UI, email, notification, or broader session replacement scope.
</specifics>

<deferred>
## Deferred Ideas

None - analysis stayed within phase scope.

### Reviewed Todos (not folded)
No matching todos were found for this phase.
</deferred>

---

*Phase: 45-ssh-and-session-runtime-hardening*
*Context gathered: 2026-04-30*
