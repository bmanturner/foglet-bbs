---
phase: 39-app-shell-simplification
reviewed: 2026-04-29T00:00:00Z
depth: standard
files_reviewed: 34
files_reviewed_list:
  - lib/foglet_bbs/tui/app.ex
  - lib/foglet_bbs/tui/render_fixtures.ex
  - lib/foglet_bbs/tui/screen.ex
  - lib/foglet_bbs/tui/screens/board_list.ex
  - lib/foglet_bbs/tui/screens/main_menu.ex
  - lib/foglet_bbs/tui/screens/moderation.ex
  - lib/foglet_bbs/tui/screens/new_thread.ex
  - lib/foglet_bbs/tui/screens/new_thread/state.ex
  - lib/foglet_bbs/tui/screens/post_composer.ex
  - lib/foglet_bbs/tui/screens/post_reader.ex
  - lib/foglet_bbs/tui/screens/sysop.ex
  - lib/foglet_bbs/tui/screens/thread_list.ex
  - lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex
  - lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex
  - test/foglet_bbs/tui/app_runtime_contract_test.exs
  - test/foglet_bbs/tui/app_struct_test.exs
  - test/foglet_bbs/tui/app_test.exs
  - test/foglet_bbs/tui/layout_smoke_test.exs
  - test/foglet_bbs/tui/render_snapshots/account.txt
  - test/foglet_bbs/tui/render_snapshots/board_list.txt
  - test/foglet_bbs/tui/render_snapshots/main_menu.txt
  - test/foglet_bbs/tui/render_snapshots/post_reader.txt
  - test/foglet_bbs/tui/render_snapshots/thread_list.txt
  - test/foglet_bbs/tui/screen_test.exs
  - test/foglet_bbs/tui/screens/board_list_test.exs
  - test/foglet_bbs/tui/screens/main_menu_test.exs
  - test/foglet_bbs/tui/screens/moderation_test.exs
  - test/foglet_bbs/tui/screens/new_thread_test.exs
  - test/foglet_bbs/tui/screens/post_composer_test.exs
  - test/foglet_bbs/tui/screens/post_reader_test.exs
  - test/foglet_bbs/tui/screens/sysop_test.exs
  - test/foglet_bbs/tui/screens/thread_list_test.exs
  - test/foglet_bbs/tui/widgets/chrome/breadcrumb_migration_test.exs
  - test/foglet_bbs/tui/widgets/chrome/screen_frame_test.exs
findings:
  blocker: 1
  warning: 8
  info: 5
  total: 14
status: issues_found
---

# Phase 39: Code Review Report

**Reviewed:** 2026-04-29
**Depth:** standard
**Files Reviewed:** 34
**Status:** issues_found

## Summary

Phase 39 collapses the App from a god-state aggregator into a thin shell that
owns lifecycle, routing, broadcast fan-out, and `user:<id>` PubSub only.
Per-screen state has migrated cleanly into `state.screen_state[<screen>]`
slots, the `%TUI.App{}` struct now has the 8 declared fields and none of the
seven legacy ones, and the polymorphic `subscriptions/2` and
`:on_route_enter` mechanisms are wired through `function_exported?/3` guards
in a way that degrades cleanly for screens that don't implement them.

Findings cluster around two themes:

1. **A real first-paint regression for SSH-key pre-authenticated users**
   landing on `:main_menu` directly via `init/1` — `:on_route_enter` is only
   dispatched from `apply_effect(navigate)`, not from `init/1`, so the
   oneliner panel renders empty until the user navigates away and back.
   `app_test.exs:113`'s `refute_received {:list_recent_visible, 5}` proves
   this is the current observable behaviour. (CR-01).
2. **Five tests still violate the "no text-presence" rule** (and worse, one
   pattern reads source files and greps the source string for substrings
   instead of asserting behaviour). These don't break the build but degrade
   the value of the test suite per `AGENTS.md`'s explicit guidance.

A handful of smaller defects (post_composer width hard-coded at 80 because
`State.from_context/1` doesn't propagate `terminal_size`, single-arg
`screen_module_for/1` will FunctionClauseError on an unknown screen,
`Moderation.update/3` Q-handler drops context, `legacy_state` shim still
present in `post_reader` though Plan 39-07 was supposed to remove it) are
called out as warnings.

The legacy `handle_key/2` paths in PostComposer / NewThread / PostReader /
Moderation / Sysop still write to App-shape fields that no longer exist on
`%App{}` (`current_screen`, `modal`). These won't crash because the legacy
test paths build plain maps, not `%App{}` structs, but the dual code paths
should be deleted in a follow-up phase — they make the screen modules
much harder to read than they need to be.

## Critical Issues

### CR-01: Initial mount via `App.init/1` skips `:on_route_enter`, leaving authenticated screens un-hydrated

**Files:**
- `lib/foglet_bbs/tui/app.ex:242-271`
- `lib/foglet_bbs/tui/app.ex:744-752`
- `lib/foglet_bbs/tui/screens/main_menu.ex:143-149`

**Issue:** `init/1` calls `maybe_init_initial_screen_state/1` which only routes
through `init_route_screen_state/3` (calling `module.init/1`). It does NOT
call `maybe_dispatch_route_entry/3`, so the `:on_route_enter` reducer message
never reaches the screen on initial mount. `apply_effect(navigate, ...)` is
the only call site that dispatches `:on_route_enter` (`app.ex:138`).

Concrete impact: an SSH-pubkey-authenticated user whose context arrives in
`init/1` with `current_user` already populated lands on `:main_menu`. The
`MainMenuState` is constructed with `oneliner_status: :idle`, no
`load_oneliners` task fires, and the Oneliners panel renders the "No
oneliners yet." empty state until the user navigates somewhere and back.
The block comment at `app.ex:744-749` claims this is fine because
"`:on_route_enter` clause sets `:loading` before the load task fires" — but
that clause never runs. `app_test.exs:113`'s `refute_received
{:list_recent_visible, 5}` *codifies* the broken behaviour as expected.

The same hole exists for `:moderation`, `:sysop`, and (in principle)
`:post_reader` / `:thread_list` if any future flow lands a user on those
screens via `init/1` without going through `apply_effect(navigate)`. Each
screen's `:on_route_enter` clause is the canonical first-load entry — Phase
39 SPEC R4/D-04 explicitly lists "every route-entry delivers
`:on_route_enter`" as a runtime contract guarantee.

**Fix:** Dispatch `:on_route_enter` from `init/1`'s tail, after the
screen-state seeding step:

```elixir
def init(context) do
  # ... existing extraction ...
  state =
    %__MODULE__{...}
    |> maybe_init_initial_screen_state()

  # NEW: fan out :on_route_enter for parity with apply_effect(navigate).
  # Initial-mount commands are dropped — Raxol's init/1 contract returns
  # {:ok, state}, not {:ok, state, commands}. If a screen needs to fire a
  # task on initial mount, it must lift it through subscribe/1 or accept that
  # production already routes through {:set_user, user} for fresh logins.
  {state, _initial_cmds} = maybe_dispatch_route_entry(state, state.current_screen, state.route_params)

  {:ok, state}
end
```

If `init/1` cannot return commands (Raxol contract limitation), then this
needs to be solved a different way — for example, a synthetic
`{:on_route_enter}` message dispatched on first `update/2` tick, or a
post-init callback. Either way, `app_test.exs:113`'s `refute_received` is
asserting the broken behaviour and should be flipped to `assert_received`
once the underlying fix lands.

## Warnings

### WR-01: `PostComposer.State.from_context/1` ignores terminal width, locks editor at 80×10

**File:** `lib/foglet_bbs/tui/screens/post_composer/state.ex:76-90`

**Issue:** `State.new/1` accepts `:width` and `:height` opts and uses them
for `MultiLineInput.init/1`, but `from_context/1` (the canonical entry point
from the `Effect.navigate(:post_composer, ...)` path through
`init_route_screen_state/3`) constructs the state without passing them:

```elixir
def from_context(%Context{} = context) do
  params = context.route_params || %{}
  # ...
  new(
    board: ..., thread: ..., reply_to: ..., origin: ...
    # MISSING: width: terminal_width, height: editor_height
  )
end
```

Result: regardless of terminal size, the composer's MultiLineInput is
hard-wired to `width: 80, height: 10` (the `State.new/1` defaults). On a
132-column terminal the user sees a wrap at column 80 with the right third
of the editor area unused; on anything narrower than 80 columns the
editor's word-wrap will not align with the visible viewport and lines will
visually clip.

`NewThread.State.from_context/1` has the same shape (`new_thread/state.ex:96-118`)
and inherits the same bug — `width` is never threaded through from the
context's `terminal_size`.

**Fix:**

```elixir
def from_context(%Context{} = context) do
  params = context.route_params || %{}
  {w, _h} = context.terminal_size || {80, 24}

  new(
    width: max(w - 4, 20),
    height: 10,
    board: ...,
    # ... rest unchanged
  )
end
```

Apply the same in `NewThread.State.from_context/1`.

### WR-02: `Foglet.TUI.App.screen_module_for/1` raises FunctionClauseError on unknown screen

**File:** `lib/foglet_bbs/tui/app.ex:945-956`

**Issue:** The 2-arg form gracefully returns `nil` when `screen` is not in
`known_screens/0` and no override is provided (`app.ex:919-924`). The 1-arg
form has no fallback clause — it has 12 specific clauses and nothing else.
`render_screen/1`'s fallback path at `app.ex:823` calls
`screen_module_for(state.current_screen)` (single-arg) inside an
`:erlang.apply/3`. If `state.current_screen` is ever set to an unknown atom
(corrupted state, future enum drift, or a new screen wired through
`screen_modules` overrides but not added to `known_screens/0`), the runtime
crashes.

**Fix:** Add a fallback clause and surface the error explicitly:

```elixir
defp screen_module_for(:sysop), do: Screens.Sysop

defp screen_module_for(other) do
  require Logger
  Logger.error("[TUI.App] no screen module for #{inspect(other)}; falling back to :main_menu")
  Screens.MainMenu
end
```

### WR-03: `Moderation.update/3` Q-key clause drops `context` argument

**File:** `lib/foglet_bbs/tui/screens/moderation.ex:132-134`

**Issue:**

```elixir
def update({:key, %{key: :char, char: c}}, local_state, %Context{}) when c in ["Q", "q"] do
  {normalize_state(local_state), [Effect.navigate(:main_menu, %{})]}
end
```

`normalize_state/1` (single-arg) hits the `defp normalize_state(_other),
do: State.new()` clause if `local_state` is not a `%State{}` — meaning a
fresh, empty state is constructed instead of preserving the existing one.
The 2-arg form `normalize_state(local_state, context)` is the one that
correctly refreshes tab labels via `ShellVisibility.invites_visible?/2`
and preserves `%State{}` instances.

In practice the Q handler runs immediately after `screen_state` was already
hydrated by `init/1`, so `local_state` IS a `%State{}` and both forms return
the same value. But the inconsistency bites if Q is pressed before `init/1`
has run (vanishingly rare in production, but possible in tests). The
identical bug exists in `sysop.ex:115-118`.

**Fix:** Use the 2-arg form everywhere:

```elixir
def update({:key, %{key: :char, char: c}}, local_state, %Context{} = context) when c in ["Q", "q"] do
  {normalize_state(local_state, context), [Effect.navigate(:main_menu, %{})]}
end
```

### WR-04: `PostReader.legacy_state/1` shim still present despite Plan 39-07 claim

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:662-667`

**Issue:** Plan 39-07's stated goal was to remove the `legacy_state/1`
backwards-compat shim alongside the deletion of the seven App-struct fields.
The shim is still here, and it's still being called from at least nine
private helpers (`render/1`, `legacy_board_label/1`,
`legacy_thread_title_label/1`, `load_posts/2`, `apply_flush_result/3`,
`build_flush_context/1`, `advance_post/2`, `scroll_post/2`, `warm_viewport/4`).

```elixir
defp legacy_state(state) do
  case Map.get(state.screen_state || %{}, :post_reader) do
    %State{} = struct -> struct
    _ -> %State{}
  end
end
```

The shim is now structurally redundant — it just unwraps the screen-state
slot, identical to what `get_screen_state/1` does at line 653-654. The two
helpers are doing the same job under different names. Either the legacy
helper paths (`render/1`, `handle_key/2`, `load_posts/2`,
`flush_read_pointers/2`) are being kept on purpose for test compatibility,
in which case `legacy_state/1` and `get_screen_state/1` should be
consolidated into one function with one name; or those paths should be
deleted, which is what Plan 39-07's plan said. Either way the code is
strictly worse than the plan claimed it would be.

**Fix:** Delete `legacy_state/1` and route every caller through
`get_screen_state/1`. Then either delete the entire legacy `handle_key/2`
path (and the smoke tests that depend on it) or keep it but be honest about
the dual code path in the moduledoc.

### WR-05: `app.ex:531-543` legacy `handle_key/2` dispatch path still resolves screen modules and applies them

**File:** `lib/foglet_bbs/tui/app.ex:508-544`

**Issue:** The `do_update({:key, ...})` clause has a four-way `cond`/branch:
SizeGate → modal active → new-contract screen → fallback to `screen_module_for(state.current_screen)`
+ `:erlang.apply(..., :handle_key, ...)`. The fallback branch is reachable
**only** for screens that don't implement `update/3` — but every screen in
the post-39 codebase is a `@behaviour Foglet.TUI.Screen` implementer with a
real `update/3`. So this branch is dead in production today.

It's not dead in test harnesses though — at least one test fixture or smoke
test routes through it (the legacy `handle_key/2` callbacks across several
screens are explicitly kept alive for those tests, per their moduledoc).
The result is a dual code path that must be kept in sync forever or
silently diverge. The `process_screen_commands/2` machinery (lines 794-813)
exists exclusively to translate I/O dispatch tuples emitted by these legacy
handlers — none of which the new contract uses.

**Fix:** Delete the `true ->` branch in `do_update({:key, ...})` once you've
confirmed all production screens are on the new contract (which the
`new_contract_screen?/2` predicate already guarantees they are). That lets
you delete `process_screen_commands/2`, `wrap_commands/1`,
`wrap_command/1`, the legacy `handle_key/2` callbacks across screen
modules, and a measurable chunk of the legacy `render/1` paths. Keep this
narrow review's scope, but the cleanup is begging to be done.

### WR-06: `PostComposer.legacy_thread_for_submit/2` reads `PostReader`'s screen-state slot

**File:** `lib/foglet_bbs/tui/screens/post_composer.ex:446-475`

**Issue:** When `submit_reply/4` (the LEGACY path) tries to find the thread
to reply to, it falls back through:
1. `ss.thread` (composer's own state)
2. `state.screen_state[:post_reader].thread` (PostReader's state)
3. `state.route_params[:thread]`

Step 2 is a cross-screen state read — PostComposer's submit logic depends on
PostReader's screen-state slot. This violates the screen-ownership boundary
that Phase 39 was supposed to establish. The new `update/3` contract
correctly uses `state.thread_id || id_from(state.thread)` from the
composer's own State (line 518) — so the cross-screen read exists only in
the legacy submit path. Per WR-05, deleting the legacy path also deletes
this hazard.

**Fix:** Once the legacy `handle_key/2` path is removed, also remove
`legacy_thread_for_submit/2`, `legacy_reader_thread/1`, and
`legacy_route_thread/1`. Until then, document loudly that this is a hack
and not a pattern to copy.

### WR-07: Five tests assert presence of substrings in source files (`File.read!` + `=~`)

**Files:**
- `test/foglet_bbs/tui/screens/moderation_test.exs:160-161`
- `test/foglet_bbs/tui/screens/post_composer_test.exs:148-152, 266-272`
- `test/foglet_bbs/tui/screens/post_reader_test.exs:367-373, 466-472, 585-590`
- `test/foglet_bbs/tui/screens/sysop_test.exs:283-293, 1289-1295, 1868-1875, 2109-2115, 2362-2368`

**Issue:** These tests literally read the screen module's source code via
`File.read!/1` and assert that substrings (e.g.,
`"Presentation.mode_for!(:moderation)"`, `"PostCard.reader_parts"`,
`"Workspace.Inspector"`) appear in it.

```elixir
assert File.read!("lib/foglet_bbs/tui/screens/moderation.ex") =~
         "Presentation.mode_for!(:moderation)"
```

This is exactly the "test for the presence or absence of text" pattern the
project explicitly forbids in `AGENTS.md`:

> DO NOT WRITE BULLSHIT TESTS THAT TEST FOR THE PRESENCE OR ABSENCE OF TEXT.

And worse, these tests pin the implementation to a specific call shape, so
any internal refactor (e.g., extracting `Presentation.mode_for!(:moderation)`
to a helper module, changing its location in the file) breaks the test
without changing observable behaviour.

**Fix:** Replace each with a behaviour assertion against the rendered tree.
For example, instead of "the source file mentions `PostCard.reader_parts`",
assert: "rendering a thread with one post produces a header `Post 1 of 1`"
— that's actually the contract under test.

### WR-08: 332 `=~` text-presence assertions across the test suite

**Files:** All 16 test files in scope.

**Issue:** Even putting aside the source-file reads (WR-07), the test suite
contains 332 `=~` substring assertions and a meaningful fraction of them
test surface details rather than behaviour. Examples:

- `assert text =~ "Composer"` (post_composer_test.exs:159) — tests that the
  word "Composer" appears somewhere in the rendered text. Doesn't tell you
  what's actually being rendered.
- `assert text =~ "Title"` (new_thread_test.exs:531) — same critique.
- `assert text =~ "0 / 60 chars"` (new_thread_test.exs:532) — this is a
  legitimate budget-formatting assertion, but its co-occurrence with the
  surface-detail ones means a future refactor can't tell which =~ calls
  protect a real contract and which are just confidence-padding.

Per `AGENTS.md`, "DO NOT WRITE BULLSHIT TESTS THAT TEST FOR THE PRESENCE OR
ABSENCE OF TEXT." Some `=~` checks are legitimate (asserting on glyph
choices, budget format strings, key-bar contents) and should be kept; the
rest are noise that locks layout decisions in place.

**Fix:** Audit each `=~` assertion against the question "does this test fail
if a layout-only refactor changes the rendered text but preserves the
component's contract?" If yes, replace with a structural assertion against
the rendered tree (e.g., "the rendered tree contains a node of type :text
with content matching `r/^\d+ \/ \d+ chars$/` inside the budgets row").
Triage scope: WR-07's source-file reads first; the layout-pinning ones
second (the highest-density culprits are `layout_smoke_test.exs` with 70
matches and `new_thread_test.exs` with 41).

## Info

### IN-01: `app.ex:482-506` `do_update({:confirm_modal, ...})` callback shape is undocumented

**File:** `lib/foglet_bbs/tui/app.ex:481-506`

**Issue:** Modal callbacks may be `nil`, `:dismiss_modal`, or
`fun :: (state -> {state, [cmd]} | message)`. The function-form return
shape is checked with `case ... do {%__MODULE__{} = ..., cmds} -> ...`
which means a callback returning anything else (e.g., `:no_match`, an Effect
struct, an unwrapped command) silently falls through to
`do_update(msg, cleared)` — which will hit `do_update(_other, state)` and
no-op. Bug-prone.

**Fix:** Document the contract on the `Foglet.TUI.Modal` struct's `:on_confirm`
/ `:on_cancel` fields. Or wrap the callback's return value in a more
defensive way (raise on unknown shape rather than silently no-op).

### IN-02: `RenderFixtures.populate(:board_list, ...)` writes a raw map into `screen_state`

**File:** `lib/foglet_bbs/tui/render_fixtures.ex:171-187`

**Issue:** Most `populate/3` clauses use `App.put_screen_state/3` (e.g.,
`:main_menu` at line 168). The `:board_list`, `:thread_list`,
`:post_reader`, `:post_composer`, `:new_thread`, `:account`, `:moderation`,
`:sysop`, `:login`, `:register`, `:verify` clauses all use `%{state |
screen_state: %{board_list: ...}}` with a literal map and overwrite the
whole `screen_state`. This is consistent within RenderFixtures, but
inconsistent with the API contract — `put_screen_state/3` is the public
boundary helper.

**Fix:** Route every populate clause through `App.put_screen_state/3` for
consistency. Trivial change, makes the file's API surface uniform.

### IN-03: `app.ex:585-594` `:session_replaced` modal+quit pattern doesn't wait for user dismiss

**File:** `lib/foglet_bbs/tui/app.ex:587-594`

**Issue:** The handler sets a warning modal AND immediately returns
`Command.quit()` in the same tuple. Raxol will tear the runtime down on the
next tick — the user will see at most one frame of the modal before the
session ends. Compare with `:terminate_after_modal` (line 624-641) which
correctly defers the quit until the user dismisses.

**Fix:** Reuse the `:terminate_after_modal` pattern for `:session_replaced`
to give the user a chance to read the modal:

```elixir
defp do_update({:session_replaced, _user_id}, state) do
  modal = %Foglet.TUI.Modal{
    type: :warning,
    message: "Your session was replaced by a new connection. Goodbye.",
    on_confirm: fn s -> {s, [Command.quit()]} end,
    on_cancel: fn s -> {s, [Command.quit()]} end
  }
  {%{state | modal: modal}, []}
end
```

### IN-04: `MainMenu.app_state_from_local/2` reconstructs an App-shape map for legacy renderer consumption

**File:** `lib/foglet_bbs/tui/screens/main_menu.ex:457-470`

**Issue:** The new `render/2` signature (line 88) builds a `state` map by
calling `app_state_from_local(local_state, context)`, which returns a 9-key
map shaped like the pre-Phase-39 `%App{}` (with extra `recent_oneliners`,
`selected_oneliner_index`, `pending_hide_oneliner_id` flat fields). The
ScreenFrame and other helpers expect an App-shape because they were
written before Phase 39. This works, but it's a code smell — the screen
shouldn't be reconstructing a shape it now (correctly) rejects elsewhere.

**Fix:** Phase 39 is "App-shell simplification" — a follow-up phase should
push App-shape map construction OUT of screens, replacing it with explicit
calls passing `Theme.from_state(theme_input)` where `theme_input` is the
`session_context` directly. Same pattern in PostReader's `frame_state/2`,
PostComposer's `frame_state/2`, NewThread's `frame_state/2`, and
ThreadList's `frame_state/2` — five separate construction sites of
basically the same map shape.

### IN-05: `app.ex:660-665` `domain_from_session_context` discards non-map domain silently

**File:** `lib/foglet_bbs/tui/app.ex:660-667`

**Issue:**

```elixir
defp domain_from_session_context(session_context) when is_map(session_context) do
  case Map.get(session_context, :domain) do
    domain when is_map(domain) -> domain
    _ -> %{}
  end
end
defp domain_from_session_context(_session_context), do: %{}
```

A non-map `:domain` value (e.g., a stale `nil` or a list from a misshaped
test fixture) is silently coerced to `%{}` — no warning, no telemetry. If a
test misshapes the session context it will fail on a later
`get_in(domain, [:screen_modules, screen])` lookup but with no breadcrumb
back to the original misconfiguration.

**Fix:** Optional. Either add a `Logger.warning` when `:domain` is non-nil
and non-map, or assert in dev/test mode and silently coerce in prod.

---

_Reviewed: 2026-04-29_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
