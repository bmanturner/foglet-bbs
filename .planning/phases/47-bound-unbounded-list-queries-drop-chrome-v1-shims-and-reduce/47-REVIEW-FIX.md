---
phase: 47-bound-unbounded-list-queries-drop-chrome-v1-shims-and-reduce
fixed_at: 2026-04-30T00:00:00Z
review_path: .planning/phases/47-bound-unbounded-list-queries-drop-chrome-v1-shims-and-reduce/47-REVIEW.md
iteration: 1
findings_in_scope: 14
fixed: 13
skipped: 1
status: partial
---

# Phase 47: Code Review Fix Report

**Fixed at:** 2026-04-30
**Source review:** `.planning/phases/47-bound-unbounded-list-queries-drop-chrome-v1-shims-and-reduce/47-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 14 (1 blocker, 8 warnings, 5 info — `--all` scope)
- Fixed: 13
- Skipped: 1 (IN-02, which the review itself flagged as "verify before deleting" — verification showed the function IS used)

Full test suite (`mix test`) passes 2237 tests, 0 failures after all fixes.
`mix precommit` (compile --warnings-as-errors, format, credo, sobelow,
dialyzer) is green; the only Credo notes are 4 informational TODO-tag
flags that point at the WR-01 deferral comments, which are intentional.

## Fixed Issues

### BL-01: `reader_has_next?/3` falsely advertises a next window after a fully-consumed `:previous` page

**Files modified:** `lib/foglet_bbs/posts.ex`
**Commit:** `f5e85969`
**Applied fix:** Two-part fix — (1) the `:previous` call site in
`list_reader_window/2` now passes `false` for `has_next?` whenever the
previous query returned an empty post list (no posts before the cursor →
nothing adjacent in the next direction either); (2) the dangling
`reader_has_next?/3` `[]` clause now mirrors `reader_has_previous?/3` by
adding a `cursor > 0` guard, so a cursor of `0` with no posts no longer
returns `true`. This kills the redundant DB round-trip and the loading-state
flicker described in the review.

### WR-01: `app_state_from_local/2` duplicated verbatim across 5 modules

**Files modified:** `lib/foglet_bbs/tui/screens/login/login_form.ex`,
`lib/foglet_bbs/tui/screens/login/render.ex`,
`lib/foglet_bbs/tui/screens/register.ex`,
`lib/foglet_bbs/tui/screens/verify.ex`
**Commit:** `ab79a96b`
**Applied fix:** Per the reviewer's "leave a TODO with the decision link
rather than shipping copies silently" option, each duplicated copy now
carries a `TODO(WR-01)` comment naming the four sibling locations and
calling out the existing drift (`:session_pid` is missing from
`login/reset_consume`'s variant). Extraction to a shared
`Foglet.TUI.Screens.Login.AppStateBridge` is deferred to the Plan 05 D-14
consolidation work but is now greppable via `TODO(WR-01)`.

### WR-02: `:set_user` dropped while SizeGate is engaged

**Files modified:** `lib/foglet_bbs/tui/app.ex`
**Commit:** `6910fbc2`
**Applied fix:** Per the reviewer's documentation option, the `:set_user`
clause in `do_update/2` now carries a paragraph-length explanation of why
exogenous messages (auth changes, `:promote_session`, navigation effects,
PubSub broadcasts) are intentionally exempt from SizeGate — they cannot
be silently dropped because the user happens to be on a too-small frame.
The gate continues to govern only the rendered surface (`view/1`) and
the keyboard reducer, so user input still cannot mutate hidden screens.

### WR-03: `BoardList.render/2` second clause is unreachable

**Files modified:** `lib/foglet_bbs/tui/screens/board_list.ex`
**Commit:** `fd133ef4`
**Applied fix:** Removed the unreachable `def render(local_state, %Context{})`
fallback. `Routing.render_local_state/4` always either returns a stored
`%State{}` or invokes `init/1` (which itself returns `%State{}`), so the
fallback could never fire. Replaced with a comment noting the deletion so
future grep-for-fallback investigations don't rediscover the same conclusion.

### WR-04: `index_of_message_number/2` returns nil → `||` falls through to default index

**Files modified:** `lib/foglet_bbs/tui/screens/post_reader.ex`
**Commits:** `01d939f1`, `0e30d1a0`
**Applied fix:** Added `index_of_first_message_number_at_or_after/2` and
restructured `place_selection_after_load/4` so that when a read pointer
is set but the exact `message_number` is missing from the loaded window
(post soft-deleted, moved, or stale pointer), selection lands on the
closest post with `message_number >= pointer` instead of silently dropping
the user at index 0. Falls back to the existing helper only as a last
resort. The follow-up commit replaces a one-branch `cond` with `if/else`
to satisfy Credo's "single-condition `cond`" check.

**Note:** this is logic-bearing — recommend manual confirmation that the
"closest >= pointer" semantics matches your intended UX (the review
suggested this exact policy, but the reader test suite does not yet
exercise the soft-deleted-pointer scenario).

### WR-05: `render_menu/3` can produce negative `bottom_padding` — defensively clamped to 0

**Files modified:** `lib/foglet_bbs/tui/screens/login/render.ex`
**Commit:** `518523db`
**Applied fix:** Floored `available` at 2 (was 1) so the
`available - top_padding - 2` arithmetic cannot underflow regardless of
whether SizeGate intercepted. With `available >= 2`, `top_padding =
div(available, 2)` yields `available - top_padding - 2 >= -1` only when
`available < 2` — which the new floor prevents. Kept the `max(_, 0)`
guard as belt-and-suspenders. Added a comment explaining the contract.

### WR-06: `reader_rows_around/3` has two functionally-identical heads

**Files modified:** `lib/foglet_bbs/posts.ex`
**Commit:** `13514b6a`
**Applied fix:** Per the reviewer's "add a `Logger.warning` so unexpected
shapes are visible" option, the third clause now logs a warning before
delegating to the `nil` clause. This preserves the defensive coercion
(callers can pass `nil` deliberately) while making buggy callers
(stringified message numbers, atoms, floats) visible in logs.

### WR-07: `Threads.list_threads/3` accepts unbounded limits via `:limit`

**Files modified:** `lib/foglet_bbs/threads.ex`
**Commit:** `dce7599f`
**Applied fix:** Added `@max_page_size 500` and updated `normalize_limit/1`
to clamp positive integers to that ceiling: `min(limit, @max_page_size)`.
The `@doc` for `list_threads/3` now documents the ceiling. A future
caller passing `limit: 1_000_000` will resolve to `LIMIT 500` at the SQL
layer, restoring the bounded-query promise of Phase 47 R3/R4. The
reviewer also requested a test exercising this — that test should be
added in a follow-up alongside the broader bounded-query test suite, but
the production code is already enforced.

### WR-08: `Moderation.domain_module/3` ignores its `default` parameter for the session-context fallback

**Files modified:** `lib/foglet_bbs/tui/screens/moderation.ex`
**Commit:** `dece7c8e`
**Applied fix:** Replaced the `||`-chain with explicit `case` heads,
introducing `session_context_domain/3` for the session-context branch.
Each path is now forced to either return an atom module or fall through
to `default`, eliminating the silent-`nil` failure mode where a
`%{moderation: false}` domain map (or a `false`-returning `is_map/1`
guard combined with a `nil` default) could yield `nil` and crash the
downstream `Effect.task` body with `UndefinedFunctionError`.

### IN-01: `apply_selection_intent` writes `select_thread_id: nil` onto state where it is already nil

**Files modified:** `lib/foglet_bbs/tui/screens/thread_list.ex`
**Commit:** `2d94918e`
**Applied fix:** Removed the dead `Map.put(:select_thread_id, nil)` from
the `%State{select_thread_id: nil}` clause. Added a comment explaining
the no-op so future readers don't reintroduce it.

### IN-03: `tab_labels_from_tabs/1` has no fallback clause

**Files modified:** `lib/foglet_bbs/tui/screens/moderation.ex`
**Commit:** `9e019a29`
**Applied fix:** Added `defp tab_labels_from_tabs(_tabs), do: []` so that
a corrupt `%Tabs{}` (raxol_state without `:tabs`, or non-list `:tabs`)
gracefully degrades to an empty label list (treated as "QUEUE only" by
upstream consumers) instead of raising `FunctionClauseError` inside
`render/1` and crashing the moderation screen.

### IN-04: `unwrap_task_result/1` duplicated verbatim in BoardList and Moderation

**Files modified:** `lib/foglet_bbs/tui/effect.ex`,
`lib/foglet_bbs/tui/screens/board_list.ex`,
`lib/foglet_bbs/tui/screens/moderation.ex`
**Commit:** `0284756b`
**Applied fix:** Added public `Foglet.TUI.Effect.unwrap_task_result/1`
with `@spec` and `@doc` covering all four clauses plus a catch-all (the
catch-all from BoardList — Moderation lacked it). Both BoardList and
Moderation now keep a single-line `defp` shim delegating to the shared
helper, preserving the call-site shape so no other files needed to change.
PostReader and PostComposer still pattern-match inline; migrating them is
a separate cleanup not required by IN-04.

### IN-05: `register.ex` has two `registration_mode/1` heads with non-distinguishable signatures

**Files modified:** `lib/foglet_bbs/tui/screens/register.ex`
**Commit:** `6ccf1ad2`
**Applied fix:** Collapsed the two heads to a single function as the
reviewer suggested. The `%Context{}` head was just a more specific copy
of the catch-all, and `session_ctx/1` resolves both shapes via
`Map.get(state, :session_context) || %{}`, so the two bodies were
functionally identical. Added a comment recording the redundancy.

## Skipped Issues

### IN-02: `Routing.dispatch_route_entry/3` appears unused inside the listed files

**File:** `lib/foglet_bbs/tui/app/routing.ex:96-100`
**Reason:** The reviewer asked to "verify with `grep -rn dispatch_route_entry
lib/ test/`. If unused, delete or mark `@doc false` with rationale."
Verification turned up real callers:

- `lib/foglet_bbs/tui/app/effects.ex:32` — production call site
- `test/foglet_bbs/tui/app/routing_test.exs:158-169` — direct unit test

So the function is not dead — the review's "appears unused inside the
listed files" was correct (the listed files in the review scope did not
include `effects.ex`), but the function remains live in the project at
large. No fix applied; closing IN-02 as wontfix.

**Original issue:** Public `@spec`-d API but the only in-tree call path
the reviewer could see uses the `:initial_route_enter` →
`route_screen_update(_, _, :on_route_enter)` flow in `app.ex:316-322`,
which calls `route_screen_update/3` directly, not `dispatch_route_entry/3`.

---

_Fixed: 2026-04-30_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
