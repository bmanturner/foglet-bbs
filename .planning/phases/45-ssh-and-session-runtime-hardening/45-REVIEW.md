---
phase: 45-ssh-and-session-runtime-hardening
reviewed: 2026-04-29T00:00:00Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - lib/foglet_bbs/sessions/session.ex
  - lib/foglet_bbs/sessions/supervisor.ex
  - lib/foglet_bbs/ssh/cli_handler.ex
  - lib/foglet_bbs/ssh/pubkey_stash.ex
  - lib/foglet_bbs/tui/app.ex
  - lib/foglet_bbs/tui/session_context.ex
  - test/foglet_bbs/sessions/session_test.exs
  - test/foglet_bbs/sessions/supervisor_test.exs
  - test/foglet_bbs/ssh/cli_handler_test.exs
findings:
  critical: 0
  warning: 5
  info: 4
  total: 9
status: issues_found
---

# Phase 45: Code Review Report

**Reviewed:** 2026-04-29
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found

## Summary

Phase 45 introduces three coordinated changes: (1) a TTL/sweep mechanism on
`Foglet.SSH.PubkeyStash` so stale offered pubkeys cannot leak, (2) propagation
of the SSH peer descriptor and replacement context through the guest→user
promotion path with structured audit logging, and (3) a single `cleanup/2`
helper in `Foglet.SSH.CLIHandler` that gates the global ETS connection counter
behind a `counter_counted?` flag, with the test suite proving the counter is
balanced across normal close, EOF→close, lifecycle EXIT, terminate, over-limit
reject, and rate-limit reject paths.

The counter accounting work is solid — the test matrix is thorough and the
state-machine encoding (`cleanup_done?` + `counter_counted?`) reads clearly.
The PubkeyStash TTL is internally consistent across `pop` and `sweep` boundary
conditions. The audit log additions are minimally invasive.

The defects below cluster around two areas:

1. **Registry-vs-state divergence in `Session.handle_cast({:promote_to_user, …})`** —
   when registration fails, the session still mutates its identity fields. This
   creates orphaned-but-identified sessions that aren't enforceable by the
   one-session invariant. Two paths reach this defect: (a) callers that bypass
   the supervisor protocol, and (b) `replace_then_promote`'s timeout fallback
   under Registry-DOWN-not-yet-processed timing.

2. **Crash-on-error in `Supervisor.replace/2`'s timeout branch** — uses
   `:ok = DynamicSupervisor.terminate_child/2` where `replace_then_promote`
   correctly handles `{:error, _}`. The hardening was applied to one path but
   not the symmetric one.

A handful of smaller issues (per-keystroke synchronous call into Lifecycle,
double-cast on resize, `session_context.user` not updated on in-process
promotion) are flagged as warnings/info.

## Warnings

### WR-01: `Session.promote_to_user` mutates state even when Registry registration fails

**File:** `lib/foglet_bbs/sessions/session.ex:186-217`

**Issue:** In the `{:promote_to_user, user, audit}` cast handler, `Registry.register/3`
is called and an `{:error, {:already_registered, other_pid}}` result is logged
as a "protocol violation" — but execution continues and the session struct is
still merged with `user_id`, `handle`, `role`, and preferences. The result is a
process that holds an authenticated user identity in its in-memory state but
is *not* findable through `Foglet.Sessions.Registry`. One-session-per-user
enforcement (SSH-05 / D-25) silently bypasses such a session: every subsequent
`promote_guest_session` for the same `user.id` will look up the *other* pid
in the Registry, never this one, and operate on the wrong session.

This is reachable through two channels in the current code:

1. Any caller that bypasses `Foglet.Sessions.Supervisor.promote_guest_session/2`
   and calls `Session.promote_to_user/2` directly when the slot is already
   held (no compile-time enforcement prevents this).
2. The supervisor's `replace_then_promote/4` timeout fallback (see WR-03):
   after `terminate_child` succeeds the Registry has not yet processed the
   monitored process's DOWN, so when the cast lands the slot can still be
   held by the (now-dead but unregistered) `old_pid`. `Registry` removes
   entries by trapping the owner's `:DOWN`, which is asynchronous w.r.t.
   `terminate_child`'s synchronous return.

**Fix:** When registration fails, do not commit the identity merge. Either
return `{:stop, {:registry_collision, user.id}, state}` so the session dies
loudly, or refuse the merge and keep the session as a guest:

```elixir
def handle_cast({:promote_to_user, user, audit}, state) when is_map(audit) do
  case Registry.register(Foglet.Sessions.Registry, user.id, nil) do
    {:ok, _} ->
      Logger.info("Session guest promoted",
        event: :guest_promoted,
        session_pid: self(),
        user_id: user.id,
        handle: user.handle,
        ssh_peer: Map.get(audit, :ssh_peer),
        replacement: Map.get(audit, :replacement)
      )

      state =
        state
        |> Map.merge(%{user_id: user.id, handle: user.handle, role: user.role})
        |> merge_preferences(Preferences.from_user(user))

      {:noreply, state}

    {:error, {:already_registered, other_pid}} ->
      Logger.error(
        "Session promote_to_user: Registry slot for user_id=#{user.id} held by " <>
          "pid=#{inspect(other_pid)}; refusing promotion to keep one-session invariant"
      )

      # Stop loudly so the SSH channel tears down the orphan rather than
      # leaving a half-promoted session in memory.
      {:stop, {:registry_collision, user.id}, state}
  end
end
```

---

### WR-02: `Supervisor.replace/2` timeout branch raises on `terminate_child` error

**File:** `lib/foglet_bbs/sessions/supervisor.ex:185-201`

**Issue:** `replace_then_promote/4` was hardened to handle a non-supervised /
already-dead `old_pid` via a `case … do` over `terminate_child`, falling back
to `Process.exit(:kill)`. The symmetric `replace/2` path did not receive the
same treatment:

```elixir
:ok = DynamicSupervisor.terminate_child(__MODULE__, old_pid)
```

If `old_pid` exited between `Process.demonitor(ref, [:flush])` and
`terminate_child` (e.g. crashed of its own accord just past the timeout window),
`terminate_child` returns `{:error, :not_found}` and the strict `:ok =` match
crashes the *caller*. `start_session/1` runs in the calling process (CLIHandler
on a fresh connection), so a benign timing race on the old session's exit
becomes a CLIHandler crash that drops the new connection.

**Fix:** Mirror `replace_then_promote/4`'s defensive pattern:

```elixir
defp replace(old_pid, opts) do
  ref = Process.monitor(old_pid)
  send(old_pid, :replaced_by_new_session)

  receive do
    {:DOWN, ^ref, :process, ^old_pid, _reason} ->
      start_or_adopt(opts)
  after
    @replacement_timeout_ms ->
      Process.demonitor(ref, [:flush])

      case DynamicSupervisor.terminate_child(__MODULE__, old_pid) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "Sessions.Supervisor.replace: terminate_child failed (#{inspect(reason)}); " <>
              "sending EXIT to #{inspect(old_pid)}"
          )

          Process.exit(old_pid, :kill)
      end

      start_or_adopt(opts)
  end
end
```

---

### WR-03: `replace_then_promote` timeout-fallback path can land on a still-registered Registry slot

**File:** `lib/foglet_bbs/sessions/supervisor.ex:154-183`

**Issue:** When the old session does not stop within `@replacement_timeout_ms`,
the supervisor calls either `DynamicSupervisor.terminate_child/2` or
`Process.exit(old_pid, :kill)`, then casts `promote_to_user` to the guest. The
`Registry`'s removal of `old_pid` happens when the registry process receives
the corresponding `:DOWN` from its own monitor — that is asynchronous with
respect to `terminate_child`'s synchronous return and asynchronous with respect
to `Process.exit(:kill)`. Net effect: the cast can be processed by the guest
session before the Registry has cleaned up the old slot, and the guest's
`Registry.register/3` then returns `{:error, {:already_registered, old_pid}}`.

Combined with WR-01, this means a perfectly-valid-looking promote can leave
the system with the user's session in mutated-but-unregistered state. The
existing `force-terminates a session that does not stop gracefully` test
(`supervisor_test.exs:207`) works only because in that scenario the Registry
slot was registered by `holder_pid` itself synchronously and the Registry's
own monitor DOWN is delivered on the *test pid*'s next message turn — but
under load the ordering is not guaranteed.

**Fix (requires WR-01 fix first):** After the timeout fallback's terminate /
kill, wait for the Registry to actually clear the old key before casting. The
cheapest synchronization is a synchronous Registry call that lists keys (or a
`Process.monitor` on the registry's reference for `user.id`), but the most
direct fix is to poll-once-then-cast via a small synchronous `Registry.unregister`
attempt in the supervisor (which is a no-op if already gone but flushes the
registry's own message queue):

```elixir
after
  @replacement_timeout_ms ->
    Process.demonitor(ref, [:flush])
    _ = terminate_or_kill(old_pid)
    # Drain Foglet.Sessions.Registry's own mailbox so its monitor on old_pid is
    # processed and the user.id slot is cleared before we attempt to register
    # the guest under it.
    _ = :sys.get_state(Foglet.Sessions.Registry)
    Foglet.Sessions.Session.promote_to_user(guest_pid, user, audit)
end
```

This is the same `:sys.get_state(Foglet.Sessions.Registry)` synchronization
used in `supervisor_test.exs:56` to drain the registry mailbox.

---

### WR-04: `App.do_update({:promote_session, user}, …)` does not update `session_context.user`

**File:** `lib/foglet_bbs/tui/app.ex:384-395`

**Issue:** On TUI-driven login the App casts to the supervisor to promote the
guest session and then sets `current_user: user`, but `session_context.user`
(and `:user_id`, and `:pubkey_authenticated`) remain at whatever
`SessionContext` was constructed from at channel-up — for a TUI login that's
`user: nil, user_id: nil, pubkey_authenticated: false`.

Any screen or widget that reads `session_context.user` (rather than
`current_user`) will continue to see `nil` for the rest of the session even
though the user is logged in. Since both fields exist in the App struct and
both are typed (the `t()` spec lists them as separate fields), this divergence
is an invitation to bugs that read from the "wrong" one.

**Fix:** Update `session_context` in lockstep with `current_user`:

```elixir
defp do_update({:promote_session, user}, state) do
  if is_pid(state.session_pid) do
    Foglet.Sessions.Supervisor.promote_guest_session(state.session_pid, user,
      audit: %{ssh_peer: Map.get(state.session_context, :ssh_peer)}
    )
  end

  updated_context =
    state.session_context
    |> Map.put(:user, user)
    |> Map.put(:user_id, user.id)
    # Leave :pubkey_authenticated as-is — TUI-driven login is password-based
    # by definition, so promoting here does NOT make the session pubkey-auth'd.

  Effects.apply_effect(
    %{state | current_user: user, session_context: updated_context},
    Foglet.TUI.Effect.navigate(:main_menu, %{})
  )
end
```

---

### WR-05: `get_dispatcher/1` synchronous call per input event

**File:** `lib/foglet_bbs/ssh/cli_handler.ex:439-451`

**Issue:** `dispatch_events/2` is called from `handle_ssh_msg(:data, …)` and
`handle_ssh_msg(:window_change, …)`. For every batch of events it calls
`get_dispatcher/1`, which does a synchronous `GenServer.call(lifecycle_pid,
:get_full_state)`. That means every keystroke (and every resize) does a
blocking call into the Raxol Lifecycle to look up the dispatcher pid.

Two consequences:

1. **Hang surface.** If the Lifecycle is slow to respond (long render, blocked
   on I/O, deadlocked on its own subprocess), the SSH channel handler blocks
   for the default 5s timeout — during which no further channel messages,
   including `:closed`, are processed. The user sees a stuck terminal.
2. **Per-keystroke overhead.** Every input event pays a round-trip cost to
   resolve a value that almost never changes for the lifetime of the channel.

**Fix:** Resolve the dispatcher pid once at PTY start (immediately after
`Lifecycle.start_link/2` in `handle_ssh_msg(:pty, …)`) and stash it on
`%CLIHandler{}`. `dispatch_events/2` becomes a pure cast loop with no
synchronous boundary into the Lifecycle:

```elixir
{:ok, lifecycle_pid} = Raxol.Core.Runtime.Lifecycle.start_link(...)
%{dispatcher_pid: dispatcher_pid} =
  GenServer.call(lifecycle_pid, :get_full_state)

{:ok, %{state |
  lifecycle_pid: lifecycle_pid,
  dispatcher_pid: dispatcher_pid,
  width: width,
  height: height
}}
```

If a future Raxol version can rebuild the dispatcher, refresh on the EXIT
path or expose a notification for it; today it lives for the Lifecycle.

## Info

### IN-01: Double-cast on terminal resize

**File:** `lib/foglet_bbs/ssh/cli_handler.ex:162-164`, `lib/foglet_bbs/tui/app.ex:258-260`

**Issue:** `CLIHandler.handle_ssh_msg(:window_change, …)` calls
`Sessions.Session.set_terminal_size/2` directly, *and* dispatches a `:window`
event into the Raxol app where `App.do_update({:window_change, …}, …)` calls
the same `Sessions.Session.set_terminal_size/2`. Two casts per resize, both
with the identical value. Last-write-wins so it's not a correctness defect,
but it's redundant and obscures ownership of the "session knows its size"
invariant.

**Fix:** Pick one source of truth. Removing the CLIHandler-side cast is
preferable — App already has the size and is the natural owner of UI state.

---

### IN-02: `do_channel_up` over_limit branch discards incoming `state`

**File:** `lib/foglet_bbs/ssh/cli_handler.ex:222-228`

**Issue:** The over-limit reject path constructs a fresh `%__MODULE__{}` from
scratch instead of using `%__MODULE__{state | …}`. Today this is harmless
because `init/1` returns the default struct unchanged, but it's a brittle
pattern: any future field added in `init/1` (e.g. a started_at timestamp,
trace id, or counter snapshot) will be silently dropped on the rejection
path while the accepted path (line 245) preserves them.

**Fix:** Use update-syntax for symmetry: `%__MODULE__{state | over_limit: true,
channel_id: …, connection_ref: …, cleanup_done?: true, counter_counted?: false}`.

---

### IN-03: `App.do_update({:promote_session, user}, …)` silently degrades when `session_pid` is nil

**File:** `lib/foglet_bbs/tui/app.ex:384-395`

**Issue:** If `state.session_pid` is `nil` (CLIHandler couldn't start the
Sessions.Session, or non-SSH callers), the promotion call is skipped and the
user proceeds into the main menu without any backing Session process — no
heartbeats, no terminal-size updates, no replacement enforcement, and no audit
log. The path is silent: there's no info-level log marking this case.

**Fix:** When `session_pid` is `nil`, log a warning so production telemetry
can flag the "logged in without Session" condition, e.g.:

```elixir
defp do_update({:promote_session, user}, state) do
  if is_pid(state.session_pid) do
    Foglet.Sessions.Supervisor.promote_guest_session(state.session_pid, user,
      audit: %{ssh_peer: Map.get(state.session_context, :ssh_peer)}
    )
  else
    require Logger
    Logger.warning("[TUI.App] promote_session without session_pid; " <>
      "user=#{inspect(user.handle)} — Session telemetry will be missing")
  end
  ...
end
```

---

### IN-04: `PubkeyStash` legacy two-tuple entries can leak past sweep

**File:** `lib/foglet_bbs/ssh/pubkey_stash.ex:91-93`, `100-115`

**Issue:** `pop/2` accepts legacy two-tuple entries `{peer_key, public_key}`
without a timestamp, returning them as `{:ok, public_key}` regardless of age.
`sweep/2`'s match spec only matches three-tuples, so a stranded legacy entry
(written by a deployment running an older version, or by a path that bypasses
`put/2`/`put/3`) is never deleted by the periodic sweep. In normal rollout
they self-clean via `pop`, but if the corresponding connection never reaches
`ssh_channel_up` (handshake aborts after `is_auth_key/3`), the entry sits
indefinitely.

Risk is small — the field set is bounded by historical legacy state — but the
moduledoc claims sweep "removes stale orphan entries", which is not accurate
for the legacy shape.

**Fix:** Either widen the match spec to also delete two-tuple entries, or
remove the legacy branch and assert all entries are three-tuples:

```elixir
match_spec = [
  {{:"$1", :"$2", :"$3"}, [{:<, :"$3", cutoff}], [true]},
  # Legacy two-tuple entries have no TTL info; sweep them unconditionally
  # since a connection that needed them would have popped during channel_up.
  {{:"$1", :"$2"}, [], [true]}
]
```

---

_Reviewed: 2026-04-29_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
