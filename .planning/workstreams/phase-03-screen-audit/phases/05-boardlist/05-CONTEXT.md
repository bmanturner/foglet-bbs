# Phase 5: BoardList - Context

**Gathered:** 2026-04-21
**Status:** Ready for planning
**Workstream:** phase-03-screen-audit

<domain>
## Phase Boundary

Audit `board_list.ex` as a focused refinement pass while preserving current user-facing
navigation and list behavior:

- keep subscribed-board rendering through `SelectionList` + `ListRow`,
- complete the dead-code audit decision for the public `load_boards/1` hook,
- apply/confirm audit-wide rubric items (`AUDIT-05..22`) for this screen,
- evaluate loading feedback for the async boards load path,
- keep row gutters unclaimed for future milestone work.

**In scope:**
- BOARDS-01..BOARDS-05 from this workstream.
- `load_boards/1` usage audit and explicit disposition.
- `init_screen_state/1` adoption for BoardList (`AUDIT-19`).
- Section-order cleanup for `AUDIT-18` if needed.
- Loading feedback decision for the async load path.

**Out of scope:**
- New board metadata columns, badges, or status decorations in row gutters.
- Redesigning list navigation or replacing `SelectionList`/`ListRow`.
- Cross-screen refactors outside audit-required scope.
- New shared modules beyond existing Phase 0 extractions.

</domain>

<decisions>
## Implementation Decisions

### Loading feedback behavior

- **D-01:** Adopt a spinner for the BoardList loading state rather than plain static text.
  User explicitly selected spinner as the target affordance for this phase.
- **D-02:** Spinner adoption should remain tied to the real async `{:load_boards}` path
  (never decorative idle animation on non-loading states).

### Dead-code audit disposition (`load_boards/1`)

- **D-03:** Keep `BoardList.load_boards/1` as a public test seam and compatibility hook,
  but mark it `@doc false` with an explicit comment that production load ownership is
  `Foglet.TUI.App.do_update({:load_boards}, state)`.
- **D-04:** Phase summary must include the audit evidence (`rg -w load_boards test/ lib/`)
  and record why the function remains present.

### BoardList state shape

- **D-05:** Add public `init_screen_state/1` for BoardList and replace inline fallback
  literals like `%{selected_index: 0}` with calls to that initializer.
- **D-06:** BoardList is not intentionally stateless; it owns
  `state.screen_state[:board_list]` with a selected-index default.

### Guardrails for this phase

- **D-07:** Preserve existing `SelectionList` + `ListRow` usage and navigation semantics.
- **D-08:** Do not fill BoardList row gutters (reserved by `AUDIT-17` Region 2).

### the agent's Discretion

- Exact spinner widget choice between `Widgets.Progress.Spinner` and
  `Widgets.Display.Progress` (indeterminate vs determinate) as long as the selected
  widget is appropriate for board-load behavior.
- Exact helper naming for screen-state accessors beyond required
  `init_screen_state/1`.
- Exact section-order edits needed to satisfy `AUDIT-18` with minimal churn.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase requirements and rubric

- `.planning/workstreams/phase-03-screen-audit/ROADMAP.md` — Phase 5 goal,
  success criteria, and dependency framing.
- `.planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md` — `BOARDS-01..05`
  and inherited `AUDIT-05..22` constraints, especially `AUDIT-10`, `AUDIT-12`,
  `AUDIT-17`, `AUDIT-18`, and `AUDIT-19`.
- `.planning/workstreams/phase-03-screen-audit/STATE.md` — current workstream state
  and locked decision continuity.

### Workstream research

- `.planning/workstreams/phase-03-screen-audit/research/ARCHITECTURE.md` — BoardList
  audit notes, section-order guidance, and protected layout region references.
- `.planning/workstreams/phase-03-screen-audit/research/PITFALLS.md` — anti-affordance
  guardrails and reserved-region traps for BoardList.
- `.planning/workstreams/phase-03-screen-audit/research/SUMMARY.md` — phase-level
  recommendation that BoardList keeps list widgets and resolves `load_boards/1` audit.

### Prior phase context this phase inherits

- `.planning/workstreams/phase-03-screen-audit/phases/00-cross-cutting-extractions-prelude/00-CONTEXT.md`
  — Theme/Domain helper contracts used by BoardList.
- `.planning/workstreams/phase-03-screen-audit/phases/04-mainmenu/04-CONTEXT.md`
  — current workstream sparseness discipline and reserved-region framing.

### Code to read before planning

- `lib/foglet_bbs/tui/screens/board_list.ex` — audited target screen.
- `lib/foglet_bbs/tui/app.ex` — production owner of `{:load_boards}` async loading flow.
- `test/foglet_bbs/tui/screens/board_list_test.exs` — current call sites for
  `BoardList.load_boards/1` and expected behavior.
- `lib/foglet_bbs/tui/widgets/list/selection_list.ex` — existing list interaction primitive.
- `lib/foglet_bbs/tui/widgets/list/list_row.ex` — existing row rendering primitive.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable assets

- `Theme.from_state/1` and `Screens.Domain.get/2` are already available for this screen.
- `SelectionList.render/3` + `ListRow.render/3` already implement the intended board list UX.
- `ScreenFrame.render/4` already provides stable chrome and key hints.

### Established patterns

- Production board loading runs via `App.do_update({:load_boards}, state)` and
  task-based async command dispatch.
- BoardList currently uses inline `%{selected_index: 0}` defaults in multiple places;
  this is the exact AUDIT-19 normalization target.
- `load_boards/1` is referenced in tests; production behavior does not depend on it.

### Integration points

- Entering BoardList from MainMenu triggers `{:load_boards}`.
- Opening a board from BoardList transitions to `:thread_list` and dispatches
  `{:load_threads, board.id}`.
- Any loading-indicator change must preserve existing board-load command flow and
  not alter navigation key semantics.

</code_context>

<specifics>
## Specific Ideas

- User explicitly wants spinner-based loading affordance for BoardList.
- Keep visual density restrained even with spinner adoption; no extra status rows.
- Keep the test seam for `load_boards/1`, but make its non-primary role explicit in code docs.

</specifics>

<deferred>
## Deferred Ideas

- Board-row presence counts and mention/DM badges remain deferred to the milestones that own
  those features (protected Region 2).
- Any BoardList information-density expansion beyond the current name + unread model is deferred.

</deferred>

---

*Phase: 05-boardlist*
*Context gathered: 2026-04-21*
