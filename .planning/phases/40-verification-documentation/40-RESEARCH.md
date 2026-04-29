---
phase: 40
slug: verification-documentation
status: complete
researched: 2026-04-29
---

# Phase 40 — Verification & Documentation Research

## Research Question

What does the planner need to know to close the v2.0 TUI runtime migration with
green verification gates, resolved Phase 39 carry-forward items, and useful
developer documentation?

## Summary

Phase 40 should be planned as a close-gate sequence, not as new architecture.
The implementation should start by turning the Phase 39 carry-forward artifacts
into an explicit closure register, then fix the known blockers, then remove or
bound the remaining transitional runtime surfaces, then fill verification and
documentation gaps. The phase should avoid broad product, browser, routing,
visual redesign, and whole-suite test-hygiene work.

The critical source artifacts are:

- `.planning/phases/40-verification-documentation/40-SPEC.md`
- `.planning/phases/40-verification-documentation/40-CONTEXT.md`
- `.planning/phases/39-app-shell-simplification/deferred-items.md`
- `.planning/phases/39-app-shell-simplification/39-SUMMARY.md`
- `.planning/phases/39-app-shell-simplification/39-REVIEW-FIX.md`
- `lib/foglet_bbs/tui/screen.ex`
- `lib/foglet_bbs/tui/app.ex`
- `test/foglet_bbs/tui/app_runtime_contract_test.exs`
- `test/foglet_bbs/tui/layout_smoke_test.exs`
- `test/foglet_bbs/tui/screens/account_test.exs`
- `test/foglet_bbs/tui/widgets/chrome/breadcrumb_migration_test.exs`

## Carry-Forward Inventory

The planner must force every carried-forward item into a final disposition:
fixed, intentionally excluded, or still blocking with evidence.

| Source | Item | Planning implication |
|--------|------|----------------------|
| `deferred-items.md` | `account_test.exs` doomed oneliner submit failures at the BL-01 modal form lock release tests | First cleanup plan should fix `Modal.Form.submit_state` recovery through MainMenu/App modal result routing; do not delete or weaken the behavioral checks. |
| `deferred-items.md` | `board_list.ex:161` Dialyzer `pattern_match_cov` | Include a focused Dialyzer cleanup task before final precommit. |
| `deferred-items.md` | `sysop.ex:823` Dialyzer impossible pattern warning | Include a focused Dialyzer cleanup task before final precommit. |
| `39-SUMMARY.md` | Transitional callbacks `render/1`, `handle_key/2`, `init_screen_state/1` still declared and partially used | Plan must remove production App fallback dispatch and update fixtures/tests to use `init/1`, `update/3`, `render/2`; remaining compatibility helpers must be bounded as test-only or removed. |
| `39-SUMMARY.md` | Login/MainMenu/BoardList/Account/Moderation/Sysop breadcrumb completion | Plan must add explicit `breadcrumb_parts` or documented exact fallback intent with active tests. |
| `39-REVIEW-FIX.md` WR-02 / IN-02 | Legacy `handle_key/2` and `render/1` bodies remain in PostReader, PostComposer, NewThread and related tests call them directly | Plan should migrate the tests to reducer/render2 seams and delete the duplicate legacy bodies where possible. |
| `39-REVIEW-FIX.md` WR-04 | `App.take_screen_modal_submit/0` uses Process dictionary mailbox for modal submits | Not required to redesign the full modal protocol in Phase 40 unless it directly blocks BL-01. If retained, document/bound it as a runtime compatibility seam and keep tests around behavior. |
| `39-REVIEW-FIX.md` IN-03 | Text-presence assertions in migrated TUI tests | Target only known migrated-surface weak tests and new Phase 40 tests. Do not rewrite the entire test suite. |
| `39-REVIEW-FIX.md` IN-04 | `frame_state/2` App-shape maps across screens | Treat as optional cleanup only if it falls out of callback cleanup; broad `Theme.from_context/1`/`ScreenFrame` API refactor is out of scope. |

## Code Findings

### Runtime Shell

`Foglet.TUI.App` now holds the expected runtime-shell fields and generic helper
surface: `apply_effect/2`, `apply_effects/2`, `init_route_screen_state/3`,
`route_screen_update/3`, `context_for_screen_key/2`, `render_screen/1`, and
`render_local_state/4`. It still contains two legacy fallback seams that Phase
40 needs to address:

- `do_update({:key, key_event}, state)` falls back to `screen_module.handle_key/2`
  when a screen does not export `update/3`.
- `render_screen/1` falls back to `screen_module.render/1` when a screen does
  not export `render/2`.

Those fallbacks are production dispatch surfaces. Removing them is the cleanest
way to satisfy the transitional callback requirement once all known screens
export the new contract.

### Screen Behaviour

`Foglet.TUI.Screen` still declares both the new callbacks and the transitional
callbacks. The new contract is already described, but the module docs still say
the migration is in progress. Phase 40 should update the docs to make
`init/1`, `update/3`, `render/2`, and optional `subscriptions/2` the canonical
screen contract.

### Legacy Callback Search

Current live matches show production legacy callback bodies in:

- `lib/foglet_bbs/tui/screens/post_reader.ex`
- `lib/foglet_bbs/tui/screens/post_composer.ex`
- `lib/foglet_bbs/tui/screens/new_thread.ex`
- `lib/foglet_bbs/tui/screens/account.ex`
- `lib/foglet_bbs/tui/screens/moderation.ex`
- `lib/foglet_bbs/tui/screens/sysop.ex`

Several screens also still expose `init_screen_state/1`, and
`lib/foglet_bbs/tui/render_fixtures.ex` currently calls `init_screen_state/1`
for Login, Register, Verify, Account, Moderation, and Sysop. The plan should
avoid deleting `init_screen_state/1` before moving render fixtures and tests to
`init/1` or explicit state constructors.

### Modal Failure Fix

The BL-01 tests in `test/foglet_bbs/tui/screens/account_test.exs` assert four
behavioral outcomes:

- Natural Enter submit drives the form to `:submitting`.
- Failed oneliner submit transitions the modal form to `{:error, _}`.
- Failed hide-oneliner submit transitions the modal form to `{:error, _}`.
- Escape dismisses the modal after each failed submit path.

The likely fix location is MainMenu/App modal task-result handling, with
`Foglet.TUI.Widgets.Modal.Form.set_submit_state/2` used to move the retained
modal body out of `:submitting`. Preserve the tests; they are exactly the kind
of behavioral assertions Phase 40 wants.

### Breadcrumb Completion

Existing explicit `breadcrumb_parts` coverage exists for ThreadList,
PostReader, PostComposer, NewThread, and Sysop. Remaining screens that need
explicit breadcrumb behavior or active documented fallback intent are Login,
Register, Verify, MainMenu, BoardList, Account, and Moderation. The pending
`:phase39_login_breadcrumb_pending` tags in `layout_smoke_test.exs` are direct
follow-up targets.

### Render Verification

`test/foglet_bbs/tui/layout_smoke_test.exs` already defines the supported size
set `{64, 22}`, `{80, 24}`, `{132, 50}` and has helper patterns that run the
same layout engine used by the live TUI. `mix foglet.tui.render` provides
manual, deterministic, ANSI-stripped screen renders. Phase 40 should record
the exact render commands in its summary instead of creating a large new render
matrix.

## Validation Architecture

Use existing ExUnit and GSD/TUI render infrastructure. The planner should
include a validation plan that records evidence, not only code changes.

### Quick Feedback Commands

- `rtk mix test test/foglet_bbs/tui/screens/account_test.exs`
- `rtk mix test test/foglet_bbs/tui/app_runtime_contract_test.exs test/foglet_bbs/tui/app_struct_test.exs test/foglet_bbs/tui/app_test.exs`
- `rtk mix test test/foglet_bbs/tui/widgets/chrome/breadcrumb_migration_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`
- `rtk mix dialyzer`

### Full Gate Commands

- `rtk mix test`
- `rtk mix foglet.tui.render login --width 64 --height 22`
- `rtk mix foglet.tui.render main_menu --width 80 --height 24`
- `rtk mix foglet.tui.render board_list --width 132 --height 50`
- `rtk mix foglet.tui.render post_reader --width 80 --height 24`
- `rtk mix precommit`

### Evidence Artifacts

- A Phase 40 carry-forward disposition section in a new summary/evidence doc.
- A reducer/effect coverage inventory by screen family.
- A render-smoke command/result table with terminal sizes.
- Documentation linked from `lib/foglet_bbs/tui/widgets/README.md` or a nearby
  TUI README surface.

## Planning Recommendations

Recommended plan slices:

1. Close deferred blockers and create the disposition register.
2. Remove or bound legacy production callback dispatch and migrate fixtures/tests.
3. Complete breadcrumbs and targeted weak-test cleanup.
4. Fill reducer/effect and App-shell verification gaps.
5. Add screen contract docs and final evidence/precommit gates.

The plan should keep Phase 40 bounded. Do not introduce new routing/history
modules, per-screen processes, broad visual redesign, browser UI, or a full
test-suite rewrite.

## Risks And Pitfalls

- Deleting legacy callbacks before updating `render_fixtures.ex` and tests will
  break render inspection and existing test helpers.
- Replacing BL-01 with rendered-text checks would violate both the SPEC and
  AGENTS.md. Keep state/effect assertions.
- Treating all `handle_key/2` functions as forbidden would overreach: nested
  helper modules can still expose local handlers. The cleanup target is the
  `Foglet.TUI.Screen` production boundary and App fallback dispatch.
- `rtk mix precommit` may take materially longer than targeted test commands;
  use focused commands during implementation and reserve precommit for the
  final plan.

## Research Complete

This research is sufficient to plan Phase 40 without external sources.
