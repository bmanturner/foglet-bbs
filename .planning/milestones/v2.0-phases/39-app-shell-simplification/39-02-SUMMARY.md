---
phase: 39-app-shell-simplification
plan: 02
subsystem: tui

tags: [tui, screen-behaviour, optional-callback, subscriptions, contract-first, phase39]

# Dependency graph
requires:
  - phase: 39
    plan: 01
    provides: phase39_target tag exclusion + screen_test.exs pin asserting {:subscriptions, 2} appears in Foglet.TUI.Screen.behaviour_info(:optional_callbacks). This plan unblocks that pin by landing the matching behaviour declaration and removing the tag.
provides:
  - "Foglet.TUI.Screen @callback subscriptions(local_state(), Foglet.TUI.Context.t()) :: [String.t()]"
  - "subscriptions: 2 entry appended to Foglet.TUI.Screen @optional_callbacks (now seven entries: init: 1, update: 3, render: 2, render: 1, handle_key: 2, init_screen_state: 1, subscriptions: 2)"
  - "screen_test.exs default-suite pin asserting Screen.behaviour_info(:optional_callbacks) includes {:subscriptions, 2} (no longer @tag :phase39_target)"
affects: 39-03, 39-04, 39-05

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Optional behaviour callback declaration using @callback + @optional_callbacks for App-shell decoupling — screens may opt in to PubSub topic interest without central App pattern-matching."
    - "Pin-test unblocking: when the matching production code lands, the corresponding plan removes @tag :phase39_target so the test enters the default suite as the fail-loud signal."

key-files:
  created:
    - .planning/phases/39-app-shell-simplification/39-02-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/screen.ex
    - test/foglet_bbs/tui/screen_test.exs

key-decisions:
  - "[Phase 39-02]: Insert the subscriptions/2 callback declaration immediately after render/2 (the new-contract block) rather than after the transitional callbacks. The new contract block (init/1, update/3, render/2, subscriptions/2) groups Phase-34+ callbacks together; the transitional block (render/1, handle_key/2, init_screen_state/1) remains a clearly-separated legacy region. This visually mirrors the @optional_callbacks ordering, where new-contract entries precede transitional entries — except for the appended subscriptions: 2 which is placed last in @optional_callbacks per the plan's instruction. Per D-05, the new arity ordering mirrors update/3 / render/2: local_state first, Context.t() second."
  - "[Phase 39-02]: Added an explanatory @doc on @callback subscriptions citing D-05 / SPEC R6 so downstream implementers (Plans 39-03, 39-04) understand why the App calls into this rather than encoding screen-specific topic logic. Future Phase-39 work that turns transitional callbacks into the new contract can follow the same pattern."

patterns-established:
  - "App-shell decoupling pattern: optional-callback declaration for screen-driven behaviours (subscriptions/2) lets the App polymorphically dispatch to screens rather than pattern-matching on screen module identity."

requirements-completed: [APP-03]

# Metrics
duration: 6min
completed: 2026-04-29
---

# Phase 39 Plan 02: Declare Screen.subscriptions/2 Optional Callback Summary

**Added `subscriptions/2` as an optional callback on `Foglet.TUI.Screen` (declaration + `@optional_callbacks` entry) so PostReader, ThreadList, and BoardList can implement it with `@impl true` in Plans 39-03 and 39-04 without `unknown function` Dialyzer warnings; unblocked the Plan 39-01 pin test in `screen_test.exs` by removing its `@tag :phase39_target`.**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-04-29T03:47:49Z
- **Completed:** 2026-04-29T03:49:47Z
- **Tasks:** 1 / 1
- **Files modified:** 2 (`screen.ex`, `screen_test.exs`)
- **Files created:** 1 (this SUMMARY.md)

## Accomplishments

- `Foglet.TUI.Screen.behaviour_info(:optional_callbacks)` now includes `{:subscriptions, 2}`. Verified by the formerly-tagged screen_test.exs pin running green in the default suite (4 tests, 0 failures).
- The new `@callback subscriptions(local_state(), Foglet.TUI.Context.t()) :: [String.t()]` is placed in the new-contract callback block (immediately after `render/2`) with an explanatory `@doc` citing D-05 / SPEC R6, while the transitional callbacks block (render/1, handle_key/2, init_screen_state/1) is left untouched per Phase-39 / Phase-40 boundary.
- `@optional_callbacks` grows from six entries to seven; `subscriptions: 2` appended last as instructed; the existing six entries (`init: 1`, `update: 3`, `render: 2`, `render: 1`, `handle_key: 2`, `init_screen_state: 1`) all still appear.
- `rtk mix compile --warnings-as-errors` exits 0 (only dependency-side warnings from raxol; foglet_bbs compiles cleanly).
- `rtk mix dialyzer` emits exactly the three pre-existing warnings tracked in `deferred-items.md` (`app.ex:63 unknown_type ThreadEntry.t/0`, `board_list.ex:161 pattern_match_cov`, `sysop.ex:810 pattern_match`). **Zero new dialyzer warnings introduced by this plan.**
- `rtk mix format --check-formatted` returns ok; `rtk mix credo --strict` finds no issues.

### Exact Insertion Points

For downstream implementers (Plans 39-03 / 39-04) to `@impl true` confidently, here is the post-edit shape of `lib/foglet_bbs/tui/screen.ex`:

| Region | Line(s) | Content |
|--------|---------|---------|
| New-contract callbacks | 37–39 | `@callback init/1`, `update/3`, `render/2` (unchanged) |
| **NEW: subscriptions @doc + @callback** | **41–51** | **`@doc` block + `@callback subscriptions(local_state(), Foglet.TUI.Context.t()) :: [String.t()]`** |
| Transitional callbacks | 53–67 | `render/1`, `handle_key/2`, `init_screen_state/1` (unchanged) |
| `@optional_callbacks` | 69–75 | Seven entries, `subscriptions: 2` appended last |

## Task Commits

1. **Task 1: Declare subscriptions/2 optional callback on Foglet.TUI.Screen** — `0311c19` (feat)

## Files Created/Modified

### Created
- `.planning/phases/39-app-shell-simplification/39-02-SUMMARY.md` — this file.

### Modified
- `lib/foglet_bbs/tui/screen.ex` — Added `@doc` + `@callback subscriptions(local_state(), Foglet.TUI.Context.t()) :: [String.t()]` after the new-contract `render/2` callback declaration; appended `subscriptions: 2` to `@optional_callbacks`.
- `test/foglet_bbs/tui/screen_test.exs` — Removed `@tag :phase39_target` from the `test "lists subscriptions/2 in @optional_callbacks"` pin so it now runs in the default suite and serves as the fail-loud assertion that the declaration is in place.

## Decisions Made

- **Placement after `render/2` (new-contract block) rather than after transitional callbacks.** The new-contract block (init/1, update/3, render/2, subscriptions/2) is now a coherent unit; the transitional region (render/1, handle_key/2, init_screen_state/1) remains a clearly-separated legacy section. Phase 40 owns the eventual deletion of the transitional block, so keeping subscriptions/2 inside the new-contract group telegraphs that intent.
- **Per D-05, arity ordering mirrors update/3 and render/2: `local_state()` first, `Context.t()` second.** This keeps screen authors' mental model consistent across all screen-side callbacks.
- **`subscriptions: 2` appended last in `@optional_callbacks` per the plan's instruction**, even though some readers might prefer it grouped with the new-contract entries (init: 1, update: 3, render: 2). Following the plan literally avoids an unrelated reshuffle, and the linear ordering is a low-information stylistic choice — the tuple set is what matters semantically.
- **Added an explanatory `@doc` on the new callback** citing D-05 / SPEC R6 so downstream implementers (PostReader, ThreadList in 39-03; BoardList in 39-04) understand the App-shell-decoupling rationale before reaching for `@impl true`.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

- **`rtk mix precommit` does not exit 0**, but for the same three pre-existing reasons enumerated in `.planning/phases/39-app-shell-simplification/deferred-items.md`:
  - 3 dialyzer warnings (`app.ex:63 unknown_type ThreadEntry.t/0`, `board_list.ex:161 pattern_match_cov`, `sysop.ex:810 pattern_match`)
  - 2 `account_test.exs` failures at lines 1242, 1271 (`mix test` not invoked by `mix precommit`, but worth noting)

  Verified by running `rtk mix dialyzer` and observing the exact same three warnings. **This plan introduces zero new precommit failures vs. the deferred-items.md baseline.** The "rtk mix precommit exits 0" success criterion in the plan is unmeetable on top of `main` HEAD without absorbing unrelated cleanup, exactly as flagged in 39-01's SUMMARY. Per the orchestrator's note ("These are tracked in deferred-items.md and are NOT introduced by Phase 39 work. Do NOT attempt to fix them in this plan"), no remediation attempted.

## Self-Check: PASSED

Verified before commit:
- `lib/foglet_bbs/tui/screen.ex` — `grep -c '@callback subscriptions'` = 1; `grep -c 'subscriptions: 2'` = 1; existing six `@optional_callbacks` entries all still present.
- `test/foglet_bbs/tui/screen_test.exs` — line 137 (`test "lists subscriptions/2 in @optional_callbacks"`) no longer has `@tag :phase39_target` immediately above it. The describe block header is preserved.
- `rtk mix test test/foglet_bbs/tui/screen_test.exs` — 4 tests, 0 failures (3 original new-contract tests + 1 unblocked pin).
- `rtk mix compile --warnings-as-errors` — exit 0.
- `rtk mix format --check-formatted` — ok.
- `rtk mix credo --strict` — no issues.
- `rtk mix dialyzer` — exactly 3 warnings, all pre-existing per `deferred-items.md`. No new warnings.
- Commit `0311c19` — `rtk git log --oneline | grep 0311c19` returns the commit.

## Next Plan Readiness

- **Plan 39-03 (PostReader / ThreadList subscriptions/2)** can now declare `@impl Foglet.TUI.Screen` on a `subscriptions/2` implementation without Dialyzer's `unknown function` warning. Both pin tests in `post_reader_test.exs` and `thread_list_test.exs` are still gated behind `@tag :phase39_target` and will be unblocked when 39-03's implementation lands.
- **Plan 39-04 (BoardList subscriptions/2)** likewise — the `board_list_test.exs` pin is still tagged.
- **Phase 40** retains ownership of the transitional callbacks (`render/1`, `handle_key/2`, `init_screen_state/1`); they were intentionally not removed by this plan.

---
*Phase: 39-app-shell-simplification*
*Completed: 2026-04-29*
