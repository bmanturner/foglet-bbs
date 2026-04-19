---
phase: 03-ssh-server-tui
reviewed: 2026-04-19T00:00:00Z
depth: standard
files_reviewed: 12
files_reviewed_list:
  - lib/foglet_bbs/ssh/cli_handler.ex
  - lib/foglet_bbs/tui/app.ex
  - lib/foglet_bbs/tui/screens/board_list.ex
  - lib/foglet_bbs/tui/screens/login.ex
  - lib/foglet_bbs/tui/screens/main_menu.ex
  - lib/foglet_bbs/tui/screens/new_thread.ex
  - lib/foglet_bbs/tui/screens/post_composer.ex
  - lib/foglet_bbs/tui/screens/post_reader.ex
  - lib/foglet_bbs/tui/screens/register.ex
  - lib/foglet_bbs/tui/screens/thread_list.ex
  - lib/foglet_bbs/tui/screens/verify.ex
  - test/foglet_bbs/tui/app_test.exs
findings:
  critical: 3
  warning: 3
  info: 3
  total: 9
status: issues_found
---

# Phase 03: Code Review Report

**Reviewed:** 2026-04-19
**Depth:** standard
**Files Reviewed:** 12
**Status:** issues_found

## Summary

The SSH TUI implementation is structurally sound and follows the Elixir/Phoenix project conventions well. The domain-adapter injection pattern for testability, the Raxol Lifecycle integration, and the screen-state isolation per module are all well-designed. The test suite is comprehensive for the App update/view paths.

Three issues warrant immediate attention before UAT sign-off:

1. The `:persistent_term` connection counter is not race-safe and will undercount on normal disconnects.
2. The `{:terminate_after_modal, :pending_approval}` command emitted during sysop-approval registration has no handler and is silently swallowed, leaving the pending-approval user stuck on a live session indefinitely.
3. The connection counter is decremented twice per normal disconnect (`:eof` followed by `:closed`), which will eventually pin the counter at 0 and allow unlimited connections.

---

## Critical Issues

### CR-01: Connection counter decremented twice per normal disconnect

**File:** `lib/foglet_bbs/ssh/cli_handler.ex:179-192`

**Issue:** Both `handle_ssh_msg {:eof}` and `handle_ssh_msg {:closed}` call `decrement_connection_count()`. In a normal SSH client disconnect, the SSH protocol delivers `:eof` first and then `:closed` in sequence. This causes the counter to be decremented twice for every normal disconnection. After enough connections cycle through, the counter will hit the `max(0, count - 1)` floor and become permanently stuck at 0. Once pinned at 0, `check_connection_limit/0` always returns `:ok`, and the `@max_connections` limit is effectively disabled.

**Fix:** Only decrement in the `:closed` handler (which always fires on channel termination) and remove the decrement from `:eof`. Also move session and lifecycle teardown out of `:eof` — they will be handled by `:closed` or `terminate/2`.

```elixir
@impl true
def handle_ssh_msg({:ssh_cm, _conn, {:eof, _ch}}, state) do
  # eof signals the client is done sending; channel close will follow.
  {:ok, state}
end

@impl true
def handle_ssh_msg({:ssh_cm, _conn, {:closed, _ch}}, state) do
  stop_lifecycle(state.lifecycle_pid)
  _ = stop_session(state.session_pid)
  decrement_connection_count()
  {:stop, state.channel_id || 0, state}
end
```

---

### CR-02: Race condition in `:persistent_term` connection counter

**File:** `lib/foglet_bbs/ssh/cli_handler.ex:373-386`

**Issue:** `check_connection_limit/0`, `increment_connection_count/0`, and `decrement_connection_count/0` each perform a non-atomic read-modify-write on `:persistent_term`. Each SSH channel handler runs in its own process. Two simultaneous connections can both read `count = 499`, both pass the `>= 500` check, and both increment to 500 — allowing 501 total connections instead of 500. Under high concurrency the overshoot can be much larger. Additionally, `:persistent_term` is designed for infrequently updated data; frequent writes trigger a global GC of all processes on each call.

**Fix:** Use an `ETS` counter with `:update_counter` for atomic increment-with-ceiling, or a lightweight `Agent`/`GenServer`. A simple ETS approach:

```elixir
@counter_table __MODULE__.Counter

# In application start (or a one-time init):
def init_counter do
  :ets.new(@counter_table, [:named_table, :public, :set])
  :ets.insert(@counter_table, {:count, 0})
end

defp check_and_increment do
  # update_counter with a threshold guard (OTP 21+)
  try do
    :ets.update_counter(@counter_table, :count, {2, 1, @max_connections, @max_connections})
    |> case do
      n when n <= @max_connections -> :ok
      _ -> :over_limit
    end
  rescue
    _ -> :ok
  end
end

defp decrement_connection_count do
  :ets.update_counter(@counter_table, :count, {2, -1, 0, 0})
end
```

---

### CR-03: `{:terminate_after_modal, :pending_approval}` command is silently dropped

**File:** `lib/foglet_bbs/tui/screens/register.ex:233`

**Issue:** The `submit/2` function for `sysop_approved` mode returns `[{:terminate_after_modal, :pending_approval}]` in the commands list. `App.process_screen_commands/2` routes this to `do_update/2`, which has no matching clause for `{:terminate_after_modal, _}` — it falls through to the catch-all `do_update(_other, state)` and becomes a no-op. The confirmation modal is displayed, but after the user dismisses it the app returns to normal operation rather than terminating the session. A user who registers under `sysop_approved` mode can dismiss the modal and continue using the BBS as if they were logged in (the `current_user` has already been set to the newly-created pending user).

**Fix:** Add a `do_update` handler in `lib/foglet_bbs/tui/app.ex` for `{:terminate_after_modal, _}`. This command should display the modal (already done), then quit after the user dismisses it. The cleanest approach is to update the modal's `on_confirm`/`on_cancel` callbacks to issue a quit:

```elixir
# In register.ex submit/2 for sysop_approved — replace {:terminate_after_modal, ...}
# with an on_dismiss quit callback embedded in the modal:
modal = %{
  type: :info,
  title: "Account Pending",
  message:
    "Your account has been created and is pending sysop approval. You will be notified by email.",
  on_confirm: fn state -> {state, [Command.quit()]} end,
  on_cancel: fn state -> {state, [Command.quit()]} end
}

{%{state | modal: modal, register_wizard: nil}, []}
```

Alternatively, add a handler in `app.ex`:

```elixir
defp do_update({:terminate_after_modal, _reason}, state) do
  # Show whatever modal is already set, then quit when dismissed via on_confirm/on_cancel.
  modal = state.modal && Map.merge(state.modal, %{
    on_confirm: fn s -> {s, [Command.quit()]} end,
    on_cancel:  fn s -> {s, [Command.quit()]} end
  })
  {%{state | modal: modal}, []}
end
```

---

## Warnings

### WR-01: `PostReader` navigates to `:post_composer` without calling `PostComposer.init_screen_state/1`

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:67-81`

**Issue:** When the user presses `R` (reply), `PostReader.handle_key/2` sets the `:post_composer` screen state as a bare map `%{mode: :edit, reply_to: reply_to, error: nil}` — missing the required `input_state` key. `PostComposer.composer_screen_state/1` detects the missing key and silently re-initializes a fresh `MultiLineInput` from the terminal size. This works, but it is inconsistent with `MainMenu.handle_key/2` (which calls `PostComposer.init_screen_state/1` with the terminal width), and it silently discards any pre-existing composer state (e.g., a partially-written reply that was backgrounded by navigating away and back). The lazy fallback also derives width from `state.terminal_size` inside the composer, which may differ from the width available when the composer is actually rendered.

**Fix:** Call `PostComposer.init_screen_state/1` explicitly when navigating to `:post_composer`:

```elixir
def handle_key(%{key: :char, char: c}, state) when c in ["r", "R"] do
  posts = state.posts || []
  ss = get_in(state.screen_state, [:post_reader]) || %{selected_post_index: 0}
  reply_to = Enum.at(posts, ss.selected_post_index)
  {w, _h} = state.terminal_size || {80, 24}

  composer_ss =
    Foglet.TUI.Screens.PostComposer.init_screen_state(reply_to: reply_to, width: w)

  new_state = %{
    state
    | current_screen: :post_composer,
      composer_draft: "",
      screen_state: Map.put(state.screen_state, :post_composer, composer_ss)
  }

  {:update, new_state, []}
end
```

---

### WR-02: `handle_ssh_msg {:eof}` returns `{:ok, state}` leaving channel open after client EOF

**File:** `lib/foglet_bbs/ssh/cli_handler.ex:179-184`

**Issue:** After receiving `:eof` (client signals end-of-input), the handler stops the lifecycle and session but returns `{:ok, state}` instead of `{:stop, ...}`. The channel remains open. If the SSH client closes the TCP connection abnormally before the `:closed` message can be delivered, the channel process remains live with a terminated lifecycle and session. The `terminate/2` callback may fire for the channel process eventually, but there is no guarantee it does so promptly. Combined with CR-01 (double decrement), this also causes the decrement to fire here rather than in `:closed`, contributing to the undercount. Addressed by the fix in CR-01 — removing the teardown from `:eof` — but the `:ok` return is still worth noting as it keeps the channel open intentionally.

**Fix:** See CR-01 fix. By removing teardown from `:eof`, the channel stays open briefly and awaits the forthcoming `:closed`. This is the standard SSH protocol sequence. If `:closed` does not follow, `terminate/2` will clean up.

---

### WR-03: `verify.ex` resend key bypasses cooldown check for `:r`/`:R`

**File:** `lib/foglet_bbs/tui/screens/verify.ex:74`

**Issue:** The `handle_key` clause for `c in ["R", "r"]` (line 74) matches before the general typed-character clause that enforces the cooldown check (line 82). When the user is in cooldown and presses `R`, `resend_code/1` is called unconditionally — this is consistent with the intention that resending should reset the cooldown (since `resend_code_raw/1` resets `attempts` and `cooldown_until` to nil on success), but it also means a user can spam the resend endpoint without the cooldown slowing them down. If `Accounts.build_verify_code/1` is expensive or rate-limited at the DB/email layer this is acceptable, but there is no guard at the TUI layer against rapid repeated resend attempts.

**Fix:** Check `cooldown?(vs)` before proceeding in `resend_code/1`, or add an explicit resend rate limit (e.g., minimum 30-second gap between resends):

```elixir
defp resend_code(state) do
  vs = state.verify_state || %{buffer: "", attempts: 0, cooldown_until: nil}

  if cooldown?(vs) do
    {:update, %{state | modal: cooldown_modal(vs)}, []}
  else
    {new_state, cmds} = resend_code_raw(state)
    {:update, new_state, cmds}
  end
end
```

---

## Info

### IN-01: `drop_last_grapheme/1` in `login.ex` is unnecessarily O(n)

**File:** `lib/foglet_bbs/tui/screens/login.ex:138-141`

**Issue:** The helper builds a full grapheme list, measures its length, and joins a slice — four passes over the string. The equivalent used in `register.ex:74` (`String.slice(current, 0, max(String.length(current) - 1, 0))`) accomplishes the same in two passes and is consistent with the codebase convention.

**Fix:**

```elixir
defp drop_last_grapheme(""), do: ""
defp drop_last_grapheme(str), do: String.slice(str, 0, String.length(str) - 1)
```

---

### IN-02: `format_notification/2` exposes raw `inspect/1` output to users

**File:** `lib/foglet_bbs/tui/app.ex:557-563`

**Issue:** The catch-all clause and the `:dm`/`:mention` clauses all pass `inspect(payload)` directly into user-visible modal message strings. For well-formed payloads this is benign, but if payload is a complex struct (e.g., an Ecto schema with nested associations), `inspect/1` will render a verbose internal representation into the modal. This may leak schema internals or internal IDs to users.

**Fix:** Define explicit format clauses per known payload shape, and use a safe fallback for unknown kinds:

```elixir
defp format_notification(:dm, %{body: body}), do: "New message: #{body}"
defp format_notification(:mention, %{thread_title: t}), do: "You were mentioned in: #{t}"
defp format_notification(kind, _payload), do: "Notification: #{kind}"
```

---

### IN-03: `view/1` smoke test in `app_test.exs` omits `:new_thread` screen

**File:** `test/foglet_bbs/tui/app_test.exs:154-173`

**Issue:** The "renders without crashing for every current_screen value" test at line 154 iterates over all defined screens but omits `:new_thread` from the list (line 156-164). `App.screen_module_for/1` maps `:new_thread` to `Screens.NewThread`, and `Screens.NewThread.render/1` initializes a `MultiLineInput` state on first call — a crash there would not be caught by the test suite.

**Fix:** Add `:new_thread` to the screen list in the view test:

```elixir
for screen <- [
      :login,
      :register,
      :verify,
      :main_menu,
      :board_list,
      :thread_list,
      :post_reader,
      :post_composer,
      :new_thread   # <-- add this
    ] do
```

---

_Reviewed: 2026-04-19_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
