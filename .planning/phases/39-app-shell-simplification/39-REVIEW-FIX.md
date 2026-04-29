---
phase: 39-app-shell-simplification
fixed_at: 2026-04-29T09:14:00Z
review_path: .planning/phases/39-app-shell-simplification/39-REVIEW.md
iteration: 1
findings_in_scope: 9
fixed: 4
skipped: 5
status: partial
---

# Phase 39: Code Review Fix Report

**Fixed at:** 2026-04-29
**Source review:** `.planning/phases/39-app-shell-simplification/39-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 9 (0 critical + 5 warnings + 4 info)
- Fixed: 4 (WR-01, WR-03, WR-05, IN-01)
- Skipped: 5 (WR-02, WR-04, IN-02, IN-03, IN-04 — all deferred to follow-up phases per the review's own framing)

Fixes were verified by recompiling (`rtk mix compile`), running affected test
suites (post_reader, layout_smoke, moderation, sysop, app, app_struct,
app_runtime_contract), running `rtk mix format --check-formatted`, and running
`rtk mix credo --strict` on each modified file. Two pre-existing test failures
in `test/foglet_bbs/tui/screens/account_test.exs:1242,1271` (BL-01 form modal
lock release) were confirmed to fail on baseline `main` before any fix in
this pass — they are not regressions from this fix pass.

## Fixed Issues

### WR-01: Logger.warning leaks into deterministic render snapshot for every fixture-driven post_reader render

**Files modified:** `lib/foglet_bbs/tui/render_fixtures.ex`,
`test/foglet_bbs/tui/render_snapshots/post_reader.txt`

**Commit:** `e920e65`

**Applied fix:** Modified `populate(:post_reader, …)` in `RenderFixtures` to
call `PostReader.prepare_after_load/3` after writing the initial
`%PostReader.State{}` into `screen_state`. `prepare_after_load/3` is the same
public seam the production `:posts_loaded` task_result path uses — it warms
`render_cache` for the selected post (via `warm_cache_for_index/4`) and warms
the viewport (via `warm_viewport/4`). With the cache pre-populated,
`render_post_content/5` now takes its cache-hit branch on every fixture render
and the `Logger.warning("[PostReader] render cache miss …")` line no longer
fires. The warmed `%State{}` is written back into `screen_state` so subsequent
renders see the populated cache.

The committed snapshot at `test/foglet_bbs/tui/render_snapshots/post_reader.txt`
was updated to drop the leaked warning header line. Verified by re-running
`rtk mix foglet.tui.render post_reader` and inspecting stdout — no warning.

This implements **option (a)** from the review's fix sketch (warm in fixture,
exercise more of the production code path) rather than **option (b)** (drop
to `Logger.debug/1`), per the review's own preference.

### WR-03: `update_screen_state/2` and `put_sysop_state/2` defensively wrap `state.screen_state || %{}`

**Files modified:** `lib/foglet_bbs/tui/app.ex`,
`lib/foglet_bbs/tui/screens/moderation.ex`,
`lib/foglet_bbs/tui/screens/sysop.ex`

**Commit:** `da6ab53`

**Applied fix:** Removed the `|| %{}` fallback at all three call sites flagged
in the review:

- `App.put_screen_state/3` (`app.ex:103`) now does
  `Map.put(state.screen_state, key, local_state)` directly — no nil hedge.
- `Moderation.update_screen_state/2` (`moderation.ex:617`) now uses
  `state.screen_state` instead of `Map.get(state, :screen_state) || %{}`.
- `Sysop.put_sysop_state/2` (`sysop.ex:686`) now uses `state.screen_state`
  instead of `state.screen_state || %{}`.

Each site has a `WR-03`-tagged comment explaining the post-Phase-39
invariant: `%App{}` defaults `screen_state` to `%{}` and no in-tree path
rewrites it to nil, so the fallback was dead defense. If a future refactor
breaks the invariant, the resulting `BadMapError` should be loud and local —
not silently absorbed across a handful of defensive sites. The comment in
`sysop.ex` that previously justified the hedge as a "future App-shape
construction" hedge was rewritten to point to WR-03.

The review explicitly listed three sites; `app.ex:97` (`screen_state_for/2`)
has the same hedge but was not flagged — left alone to match the review's
scope. Tests: 293 tests across moderation/sysop/app suites pass.

### WR-05: `screen_module_for/2` with a stale `domain.screen_modules` override silently substitutes a screen module not in `known_screens/0`

**Files modified:** `lib/foglet_bbs/tui/app.ex`

**Commit:** `8b25f57`

**Applied fix:** Rewrote the override branch to validate with
`Code.ensure_loaded?/1`. The `cond` now has three branches:

1. Override is a real, loadable atom → return it.
2. Override is a real atom but NOT loadable (typo, deleted module, stale
   fixture) → emit `Logger.warning(…)` describing the bad override and the
   screen it was registered under, then fall back to the built-in resolver
   via the new `maybe_known_screen_module/1` helper.
3. No override (or non-atom) → fall back to `maybe_known_screen_module/1`.

`maybe_known_screen_module/1` enforces `screen in known_screens()` before
calling the single-arg `screen_module_for/1`, mirroring the asymmetry the
review flagged. This eliminates the silent-failure mode where a typo'd
override was returned to callers whose downstream
`function_exported?/3` checks would short-circuit cleanly to `{state, []}`
with no developer signal. 142 app tests pass after the change.

### IN-01: `current_route/1` doc string says "Phase 34 transition"; `apply_effect/2 :navigate` clause is stale

**Files modified:** `lib/foglet_bbs/tui/app.ex`

**Commit:** `5048be1`

**Applied fix:** Refreshed three docstring sites whose Phase 34 / mid-migration
language outlived the migration:

1. **`@moduledoc`** — Replaced the line "each screen is a pure render/1 +
   handle_key/2 pair" with the post-Phase-39 description of the 8-field App
   shell, screen-owned `%State{}` keyed under `screen_state`, and the
   `update/3` + `render/2` + optional `subscriptions/2` reducer contract.
   Added an explicit "Per-screen UI state" entry to the State Flow block.

2. **`current_route/1` docstring** — Removed the "During the Phase 34
   transition…" sentence and replaced it with a direct description of the
   route-encoding contract: atom alone when `route_params` is empty, or
   `{screen, params}` tuple when non-empty.

3. **`apply_effect/2` docstring** — Replaced the one-line
   "Interprets one Phase 34 runtime effect" tag with a real description of
   how Effects flow from screen reducers through `update/3` and how the
   `:navigate` and `:modal` payloads are interpreted against the shell.

Per the review note that "phase number references should be removed —
they age poorly and confuse future readers", three Phase-34 references are
gone. Phase references that still serve as architectural pointers
(`Phase 39 D-06, D-22, R7` for the subscriptions/2 callback) are retained —
those resolve to design-doc anchors rather than describing a transitional
state. 134 tests across `app_struct_test` and `app_test` pass.

## Skipped Issues

### WR-02: Three screens carry a full duplicate `handle_key/2`+`render/1` legacy implementation

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:400-450, 442-650`,
`lib/foglet_bbs/tui/screens/new_thread.ex:296-465, 584-653`,
`lib/foglet_bbs/tui/screens/post_composer.ex:158-209, 368-428`

**Reason:** Skipped per the review's own framing. The review's **Fix:** is
"File a follow-up phase to delete the legacy `handle_key/2` and `render/1`
implementations once the production runtime path through `App.update/2` no
longer exercises them" — i.e., the review explicitly defers the work to a
new phase rather than asking for it in-place. Attempting a partial deletion
in this fix pass would either leave the same drift surface in fewer screens
(no improvement to the structural concern) or expand to a full multi-screen
refactor outside the review-fix scope. Tracked for follow-up.

### WR-04: `take_screen_modal_submit/0` uses Process dictionary as cross-screen mailbox

**File:** `lib/foglet_bbs/tui/app.ex:799-803, 916-922`,
`lib/foglet_bbs/tui/screens/main_menu.ex:561-564`

**Reason:** Skipped — this requires changing the `Modal.Form` `:on_submit`
callback contract across all callers and routing the submit through standard
`do_update/2` dispatch rather than the Process dictionary side-channel. The
fix touches App, Modal.Form, and every screen that currently uses the
Process-dict stash; it is a structural change to the modal-submit protocol,
not a localized fix. The review's own fix sketch ("Pass the submit
destination through the Modal.Form struct itself rather than the Process
dictionary") sketches a redesign rather than a patch. Best handled as a
follow-up phase with explicit migration steps for each producer/consumer
pair. Tracked for follow-up.

### IN-02: `legacy_view`/`legacy_board_label`/`legacy_thread_title_label`/`get_screen_state` chain in `PostReader.render/1` is dead at runtime

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:274-315`

**Reason:** Skipped — same scope as WR-02. The review explicitly says: "Same
as WR-02 — pick a phase to delete the legacy renderers." The legacy
renderers in PostReader are kept alive only by tests that call `render/1`
directly; deleting them requires updating those tests in tandem. That is
phase-scoped work, not a review-fix. Tracked alongside WR-02.

### IN-03: Test files contain extensive text-presence assertions

**File:** `test/foglet_bbs/tui/screens/post_composer_test.exs`,
`test/foglet_bbs/tui/screens/post_reader_test.exs`,
`test/foglet_bbs/tui/screens/sysop_test.exs`,
`test/foglet_bbs/tui/widgets/chrome/screen_frame_test.exs`

**Reason:** Skipped — the review itself classifies this as inherited
tech-debt and explicitly states: "Track as a tech-debt item; not gating for
Phase 39." Replacing ~50 assertions across four test files would be a
sweeping cleanup pass that mixes mechanical translation
(`text =~ "Edit"` → `composer_ss(s).mode == :edit`) with case-by-case
judgment about which assertions are actually visual-contract tests
(layout_smoke glyphs, per the review's exception) versus arbitrary text
greps. Per the review's framing, this belongs in a separate cleanup phase
rather than a review-fix iteration.

### IN-04: `frame_state/2` constructs ad-hoc App-shape maps for `Theme.from_state/1` and `ScreenFrame.render/4` consumption

**File:** `lib/foglet_bbs/tui/screens/post_composer.ex:542-551`,
`lib/foglet_bbs/tui/screens/post_reader.ex:989-1005`,
`lib/foglet_bbs/tui/screens/thread_list.ex:365-374`,
`lib/foglet_bbs/tui/screens/new_thread.ex:717-726`,
`lib/foglet_bbs/tui/screens/main_menu.ex:457-470`,
`lib/foglet_bbs/tui/screens/board_list.ex:432-441`,
`lib/foglet_bbs/tui/screens/moderation.ex:390-399`,
`lib/foglet_bbs/tui/screens/sysop.ex:699-708`

**Reason:** Skipped — the review's framing is "Track as cleanup. Adding
`Theme.from_context/1` and a `ScreenFrame.render/4` clause that accepts
`%Context{}` would reduce 8 helpers to 0…" The fix is an API addition to
two widget/theme modules followed by a coordinated rewrite of 8 screens.
That is a small refactor phase, not a review-fix patch — and dropping just
one or two of the 8 helpers without adding the new API would not move the
needle on the structural concern (drift across the remaining 6+). Tracked
for follow-up.

---

_Fixed: 2026-04-29_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
