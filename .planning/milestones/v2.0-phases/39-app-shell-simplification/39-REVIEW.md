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
  - test/test_helper.exs
findings:
  critical: 0
  warning: 5
  info: 4
  total: 9
status: issues_found
---

# Phase 39: Code Review Report

**Reviewed:** 2026-04-29
**Depth:** standard
**Files Reviewed:** 34
**Status:** issues_found

## Summary

The Phase 39 simplification holds up structurally: `%Foglet.TUI.App{}` is now an
8-field runtime shell (verified by `app_struct_test.exs`), the screen-owned
`%State{}` types are consistently applied, and the optional
`Foglet.TUI.Screen.subscriptions/2` callback is honored by the App shell
(`app.ex:444-453`) and only implemented by screens that actually need it
(BoardList, ThreadList, PostReader). I could not find a single direct
dot-access of any of the seven deleted App fields (`current_board`,
`current_thread`, `current_thread_list`, `posts`, `read_position`,
`composer_draft`, `board_list`) outside of comments — that guarantee is the
load-bearing post-condition for this phase, and it holds.

That said, the cleanup is incomplete in places. PostReader, NewThread, and
PostComposer each retain a fully-populated legacy `handle_key/2` + `render/1`
codepath sitting alongside the new `update/3` + `render/2` reducer, with both
paths duplicating non-trivial business logic (board picker, body-input
forwarding, submit, flush). Two of these legacy paths still write
`current_screen` directly on the App struct, then are expected to coexist with
the new effect-dispatch flow. This duplication is the biggest single risk
surface the phase introduces — drift between the two implementations of the
same flow is exactly the kind of bug a future maintainer is most likely to
introduce.

The render-cache miss warning (`post_reader.ex:339`) leaks a real
`Logger.warning` line into the deterministic render snapshot
(`render_snapshots/post_reader.txt:3`) every time the fixture renderer runs —
indicating the fixture-render path takes the cache-miss branch on every
invocation, not just in tests.

Findings below are split into BLOCKER (none here) and WARNING / Info per the
review contract.

## Warnings

### WR-01: Logger.warning leaks into deterministic render snapshot for every fixture-driven post_reader render

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:336-344` and `test/foglet_bbs/tui/render_snapshots/post_reader.txt:3`

**Issue:** `render_post_content/5` calls `Logger.warning("[PostReader] render cache miss for post=#{post.id} width=#{w}")` whenever `ss.render_cache[{post.id, w}]` is missing for the selected post. The new-contract path (`render_local_post_content/5` at line 377) routes through this same helper, so the warning fires on every render where the cache hasn't been pre-warmed by `warm_selected_post/2` (called from `:on_route_enter` → `:load` → `task_result :load_posts`).

`Foglet.TUI.RenderFixtures.populate(:post_reader, …)` (lines 204-226 of `render_fixtures.ex`) constructs the `%PostReader.State{}` with `posts: posts, status: :loaded` but never calls `warm_selected_post/2` or `warm_cache_for_index/4` on the selected post. The result is captured in the committed snapshot at `render_snapshots/post_reader.txt:3`:

```
22:36:16.301 [warning] [PostReader] render cache miss for post=p-1 width=80
```

This is a real runtime warning — every developer running `mix foglet.tui.render post_reader` and every test that touches the fixture will emit it. It also means the deterministic snapshot file embeds a timestamp (`22:36:16.301`) that will diff on every regeneration, defeating the "diffs cleanly across runs" guarantee documented in `AGENTS.md`.

**Fix:** Either (a) warm the cache + viewport in the fixture before returning state, mirroring the production `:load` task_result path:

```elixir
defp populate(:post_reader, state, _size) do
  board = hd(synthetic_boards())
  threads = synthetic_threads(board)
  thread = hd(threads)
  posts = synthetic_posts(thread)

  post_reader_state =
    PostReader.State.new(
      board: board,
      board_id: board.id,
      thread: thread,
      thread_id: thread.id,
      posts: posts,
      status: :loaded,
      selected_post_index: 0
    )
    |> PostReader.warm_for_fixture(state, posts, 0)   # new public seam, or
                                                      # call prepare_after_load/3

  ...
end
```

…or (b) drop the warning to `Logger.debug/1` since it is a render-cache miss, not an error condition. Option (a) is preferable because it exercises more of the production code path in the snapshot and produces deterministic output.

### WR-02: Three screens carry a full duplicate `handle_key/2`+`render/1` legacy implementation that diverges from the new `update/3`+`render/2` reducer

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:400-450, 442-650`; `lib/foglet_bbs/tui/screens/new_thread.ex:296-465, 584-653`; `lib/foglet_bbs/tui/screens/post_composer.ex:158-209, 368-428`

**Issue:** Each of PostReader, NewThread, and PostComposer keeps both:

- the new contract: `update/3` + `render/2` + screen-owned `%State{}` flowing through `Effect`s
- the legacy contract: `handle_key/2` + `render/1` + direct `state.screen_state` writes + `{:terminate, …}` / `{:load_posts, …}` / `{:load_threads, …}` command tuples handled by App's `process_screen_commands/2`

The two paths duplicate non-trivial business logic. Specific drift observations:

1. **NewThread** — `do_create_thread/5` (legacy, `new_thread.ex:607-653`) deletes `:new_thread` from `screen_state`, sets `current_screen: :thread_list`, and emits a `{:load_threads, board.id}` command tuple. The new path (`update({:task_result, :create_thread, …}, …)` → `handle_create_thread_success/4`, lines 555-566) emits `Effect.navigate(:thread_list, %{select_thread_id: thread.id, …})` and lets ThreadList's screen-owned `:on_route_enter` re-load. The two flows initialize ThreadList's local state differently (the legacy path sets `selected_index: 0` via a plain map; the new path passes `select_thread_id` so ThreadList resolves the index).

2. **PostComposer** — `submit_reply/4` legacy (`post_composer.ex:406-428`) does an *inline synchronous* `posts_mod.create_reply(...)` call inside the screen, while `submit_local/2` (lines 501-529) wraps the same call in an `Effect.task` for off-process execution. The legacy path will block the dispatcher on a slow DB call; the new path will not. Both ship.

3. **PostComposer** — legacy `handle_key/2` opens a modal directly via `state | modal: %Foglet.TUI.Modal{...}`; new path emits `Effect.open_modal/1` (which goes through `apply_effect/2`). If a future maintainer adds modal-state instrumentation only at the Effect boundary, the legacy path silently bypasses it.

4. **PostReader** — legacy `advance_post/2` (lines 742-784) and `scroll_post/2` (786-818) write the screen state directly back through `state.screen_state`; new `advance_local_post/3` and `scroll_local_post/3` (lines 876-910) thread through `%State{}` cleanly. Both implement subtly different read-pointer seeding semantics (legacy uses `legacy_thread`, new uses `seed_pending_read_position/1`).

The legacy sections are commented "remains for compatibility tests / older smoke tests only" but I could not find a roadmap entry committing to their removal, and Phase 39 does not delete them.

**Fix:** File a follow-up phase to delete the legacy `handle_key/2` and `render/1` implementations once the production runtime path through `App.update/2` no longer exercises them (the `new_contract_screen?/2` guard in `app.ex:538` already short-circuits to `route_screen_update/3` for any screen that defines `update/3`, so the legacy paths are dead at runtime — only their tests keep them alive). At minimum, for the next phase: pick one screen and delete it as a proof point. The longer this duplication ships, the higher the chance a future fix lands in only one of the two paths.

### WR-03: `update_screen_state/2` and `put_sysop_state/2` defensively wrap `state.screen_state || %{}`, but `%App{}` never sets `screen_state` to nil — defensive code masks a contract violation

**File:** `lib/foglet_bbs/tui/screens/moderation.ex:617`, `lib/foglet_bbs/tui/screens/sysop.ex:686`

**Issue:** Both call sites read:

```elixir
new_screen_state = Map.put(Map.get(state, :screen_state) || %{}, :moderation, ss)
```

and

```elixir
new_screen_state = Map.put(state.screen_state || %{}, :sysop, sysop_ss)
```

`%App{}` defaults `screen_state: %{}` (`app.ex:66`), and there is no clause anywhere in App that writes `screen_state: nil`. The `|| %{}` fallback is therefore dead defense — it cannot fire under any in-tree code path. The Sysop comment on line 681-684 explicitly acknowledges this ("The App default keeps `state.screen_state` as `%{}`, but…") and justifies the guard as a hedge against a "future App-shape construction (e.g. a typed-struct refactor)."

The hedge is well-intentioned but counterproductive: `%App{screen_state: nil}` would already crash earlier in the screen pipeline (e.g. `app.ex:97` `Map.get(screen_state || %{}, key)` does the same hedge, but `route_screen_update/3` and `screen_state_for/2` both pattern-match on `%__MODULE__{screen_state: screen_state}` which would fail-fast on a non-map). Spreading the hedge across a handful of call sites just buys partial coverage, and any future refactor that does set `screen_state: nil` will have to be hunted across N defensive sites instead of caught by the type system.

**Fix:** Drop the `|| %{}` fallback in `moderation.ex:617`, `sysop.ex:686`, and `app.ex:103` (`Map.put(state.screen_state || %{}, key, local_state)`). Rely on the App struct's default and let any legitimate violation crash loudly. If a hedge is genuinely needed, move it to a single helper (`Foglet.TUI.App.screen_state_map/1`) and use it everywhere.

### WR-04: `take_screen_modal_submit/0` uses Process dictionary as cross-screen mailbox — silent message loss when modals stack or interleave

**File:** `lib/foglet_bbs/tui/app.ex:799-803, 916-922` and `lib/foglet_bbs/tui/screens/main_menu.ex:561-564`

**Issue:** Modal-form submission flows through `Process.put({Foglet.TUI.App, :pending_screen_modal_submit}, {screen_key, kind, payload})` in the screen, then `Process.get/Process.delete` in App's `handle_modal_key(:form, …)` clause. This is a one-slot mailbox keyed only on the well-known atom — there is no FIFO, no per-screen lane, and no protection against two screens stashing in quick succession.

Concrete failure scenario: if a `:form` modal's `on_submit` callback is invoked and stashes a payload, then before App's `handle_modal_key(:form, …)` processes it the user manages to re-trigger another submit (e.g. a programmatic re-open + submit, or a Modal.Form bug that fires `on_submit` twice), the **first** payload is overwritten silently and silently discarded. Worse, if a screen mistakenly stashes for the wrong `screen_key` atom, App's `route_screen_update/3` will route the payload to the named-but-not-current screen, where it lands in the catch-all `update(_message, …) → {state, []}` clause and is dropped without a log line.

The pattern is already isolated to one well-known atom, so the blast radius is small in practice — the MainMenu oneliner composer is the only producer. But the mechanism is unsound by construction; it does not scale to a second concurrent modal flow without bug.

**Fix:** Pass the submit destination through the Modal.Form struct itself rather than the Process dictionary. `Modal.Form.init/1` already accepts `:on_submit` — change the convention so callers pass the destination tuple as part of the `on_submit` callback's return value (e.g. `on_submit: fn payload -> {:screen_modal_submit, :main_menu, :oneliner_composer, payload} end`), which App then routes via the standard `do_update/2` dispatch. That removes the side-channel entirely.

### WR-05: `screen_module_for/2` with a stale `domain.screen_modules` override silently substitutes a screen module not in `known_screens/0`, bypassing route validation

**File:** `lib/foglet_bbs/tui/app.ex:959-988`

**Issue:** The screen-module resolver looks like:

```elixir
defp screen_module_for(%__MODULE__{} = state, screen) do
  case get_in(domain_from_session_context(state.session_context), [:screen_modules, screen]) do
    module when is_atom(module) and not is_nil(module) -> module
    _other ->
      if screen in known_screens() do
        screen_module_for(screen)
      else
        nil
      end
  end
end
```

The override branch (`module when is_atom(module) and not is_nil(module)`) accepts **any atom** without checking that:

1. `Code.ensure_loaded?(module)` succeeds, or
2. The module implements the `Foglet.TUI.Screen` behaviour, or
3. `screen` is in `known_screens/0` at all.

Consequence: a test fixture or a stale session_context that sets
`domain.screen_modules: %{login: :SomeNonexistentModule}` (or worse, a typo-ed
`Some.Real.Module` that doesn't have `update/3`) will be returned to callers
that downstream do `Code.ensure_loaded?/1 + function_exported?/3` checks. The
checks short-circuit cleanly to `{state, []}`, but **silently** — no log, no
crash, no test signal. The user just sees an unresponsive screen.

By contrast, the no-override path (line 964-969) does enforce `screen in known_screens()` and returns `nil` (not the typo'd module). The asymmetry is a footgun: legitimate test overrides bypass the gate that production routes hit.

**Fix:** Validate the override the same way as the built-in path:

```elixir
defp screen_module_for(%__MODULE__{} = state, screen) do
  override = get_in(domain_from_session_context(state.session_context), [:screen_modules, screen])

  cond do
    is_atom(override) and not is_nil(override) and Code.ensure_loaded?(override) ->
      override

    is_atom(override) and not is_nil(override) ->
      require Logger
      Logger.warning("[TUI.App] domain.screen_modules[#{inspect(screen)}] = #{inspect(override)} is not loadable; falling back")
      maybe_known_screen_module(screen)

    true ->
      maybe_known_screen_module(screen)
  end
end

defp maybe_known_screen_module(screen) do
  if screen in known_screens(), do: screen_module_for(screen), else: nil
end
```

That logs the bad override but still falls back gracefully — no silent failure.

## Info

### IN-01: `current_route/1` doc string says "Phase 34 transition"; comment in `apply_effect/2 :navigate` clause says "the storage key for a screen route"; both are stale

**File:** `lib/foglet_bbs/tui/app.ex:68-79`

**Issue:** The `current_route/1` docstring still describes Phase 34 transitional state ("During the Phase 34 transition App still stores…"), and the body comment style is mid-migration. With Phase 39 complete, App is now the canonical structure, not a transitional one.

**Fix:** Refresh docstrings and module-level comments to describe the post-Phase-39 invariants (8-field shell, screen-owned state, optional subscriptions/2 callback). The phase number references should be removed — they age poorly and confuse future readers.

### IN-02: `legacy_view`/`legacy_board_label`/`legacy_thread_title_label`/`get_screen_state` chain in `PostReader.render/1` is dead at runtime

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:274-315`

**Issue:** The legacy `render/1` (line 274) and its helpers are documented as "for older smoke tests only" but are dead at the production runtime entry point — `app.ex:864` checks `function_exported?(module, :render, 2)` first and routes through that branch for every screen with the new contract. The legacy `render/1` is reachable only via (a) the legacy fallback at `app.ex:868`, which only fires when `render/2` is NOT exported, and (b) direct test calls.

This is the same broad concern as WR-02; calling it out separately because PostReader's `render/1` carries a particularly large legacy helper graph (`legacy_view`, `legacy.posts`, `legacy_board_label`, `legacy_thread_title_label`, `legacy_reader_thread`, `legacy_route_thread`, `legacy_thread_for_submit`) that was prefixed `legacy_` precisely because it is on its way out.

**Fix:** Same as WR-02 — pick a phase to delete the legacy renderers. Test files that exercise `render/1` should either be updated to call `render/2` with a `Context` shim, or marked for deletion alongside the legacy path.

### IN-03: Test files contain extensive text-presence assertions, contrary to AGENTS.md's "DO NOT WRITE BULLSHIT TESTS THAT TEST FOR THE PRESENCE OR ABSENCE OF TEXT"

**File:** `test/foglet_bbs/tui/screens/post_composer_test.exs:160-163, 232-235, 259-260, 275-277`; `test/foglet_bbs/tui/screens/post_reader_test.exs:411-413, 763-765, 779-784, 1039-1040`; `test/foglet_bbs/tui/screens/sysop_test.exs:251, 263, 277, 1045-1067, 1182`; `test/foglet_bbs/tui/widgets/chrome/screen_frame_test.exs:51-58`

**Issue:** A non-trivial number of tests assert by `flat =~ "Composer"`, `assert text =~ "Edit"`, `assert text =~ "Preview"`, `assert flat =~ "Replying to @alice"`, `assert flat =~ "Insufficient role to view this tab."`, etc. AGENTS.md's repo-level rule is unambiguous: text-presence/absence is not a behaviour assertion. Behavioural intent ("composer is in edit mode") should be asserted on the underlying state (`composer_ss(s).mode == :edit`, which the same files do correctly elsewhere) or on a structured renderer attribute, not the rendered string.

This is not new to Phase 39 — most of these tests pre-date the phase, and the WR-07 fix in the prior review pass replaced source-string greps with behavioural assertions per the commit log, demonstrating the team is aware of the rule. The phase did not introduce the violations; it inherited them. The smoke-test glyph assertions in `layout_smoke_test.exs` (lines 366-583) are arguably visual-contract tests of widget rendering and a closer call — those test the layout engine's positioning of glyphs, not arbitrary UI text. Those could stay; the screen-test labels should not.

**Fix:** A pass through these tests to replace `text =~ "Edit"` with `assert composer_ss(s).mode == :edit` (and similar) would tighten ~50 assertions across the screen tests. Track as a tech-debt item; not gating for Phase 39.

### IN-04: `frame_state/2` in PostComposer/NewThread/PostReader/ThreadList/etc. constructs ad-hoc App-shape maps for `Theme.from_state/1` and `ScreenFrame.render/4` consumption — duplicated across 8 screens

**File:** `lib/foglet_bbs/tui/screens/post_composer.ex:542-551`, `lib/foglet_bbs/tui/screens/post_reader.ex:989-1005`, `lib/foglet_bbs/tui/screens/thread_list.ex:365-374`, `lib/foglet_bbs/tui/screens/new_thread.ex:717-726`, `lib/foglet_bbs/tui/screens/main_menu.ex:457-470`, `lib/foglet_bbs/tui/screens/board_list.ex:432-441`, `lib/foglet_bbs/tui/screens/moderation.ex:390-399`, `lib/foglet_bbs/tui/screens/sysop.ex:699-708`

**Issue:** Eight screens build a near-identical "App-shape" map from a `%Context{}` and their local `%State{}` to satisfy `Theme.from_state/1` and `ScreenFrame.render/4` (which still expect a map with `current_screen`, `current_user`, `session_context`, `terminal_size`, `route_params`, `screen_state`). Each screen does this slightly differently — some include `route`, some `route_params`, some `session_pid`, some `screen_state: %{<key>: state}`, some not.

This is a smell: the chrome contract leaks the App shape into every screen. Either:

1. `Theme.from_state/1` and `ScreenFrame.render/4` should accept a `%Context{}` directly (preferred — eliminates 8 helpers), or
2. A single `Foglet.TUI.Context.to_render_state/2` helper should own the construction and be called everywhere.

**Fix:** Track as cleanup. Adding `Theme.from_context/1` and a `ScreenFrame.render/4` clause that accepts `%Context{}` would reduce 8 helpers to 0 and fix the structural drift between them.

---

_Reviewed: 2026-04-29_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
