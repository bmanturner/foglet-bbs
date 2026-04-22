# Phase 6: ThreadList - Context

**Gathered:** 2026-04-21
**Status:** Ready for planning
**Workstream:** phase-03-screen-audit

<domain>
## Phase Boundary

Audit `thread_list.ex` while preserving user-visible thread browsing behavior:

- keep creator/post-count/time-ago row metadata,
- keep sticky-then-recency ordering behavior,
- fix the `function_exported?/3` correctness gap with `Code.ensure_loaded/1`,
- resolve dead-code posture for `load_threads/2`,
- enforce audit-wide contracts (`AUDIT-05..22`) for this screen.

**In scope:**
- THREADS-01..THREADS-07 from this workstream.
- `Code.ensure_loaded/1` guard before arity probes (`THREADS-02`).
- `load_threads/2` dead-code disposition (`THREADS-03`).
- Loading indicator decision for async thread load (`THREADS-05`).
- `created_by` preload contract coverage (`THREADS-04`).
- `init_screen_state/1` adoption for `thread_list` (`AUDIT-19`).

**Out of scope:**
- Any redesign of row composition or thread metadata presentation.
- Any new gutter badges/highlights reserved for later milestones.
- Any replacement of `SelectionList`/`ListRow` for this screen.
- Cross-screen refactors beyond required audit scope.

</domain>

<decisions>
## Implementation Decisions

### Module-load correctness guard

- **D-01:** Add `Code.ensure_loaded(threads_mod)` before any
  `function_exported?(threads_mod, :list_threads, arity)` checks.
- **D-02:** Only probe and dispatch to `list_threads/2` or `list_threads/1` when
  module load succeeds.

### Dead-code audit disposition (`load_threads/2`)

- **D-03:** Keep `ThreadList.load_threads/2` as a public/test seam and compatibility
  hook, but mark it `@doc false` with explicit note that production loading is owned by
  `Foglet.TUI.App.do_update({:load_threads, board_id}, state)`.
- **D-04:** Document dead-code audit evidence in phase summary via
  `rg -w load_threads test/ lib/`.

### Loading feedback policy

- **D-05:** Adopt spinner-based loading feedback for ThreadList (user-selected),
  replacing plain static loading text.
- **D-06:** Spinner is tied only to real async loading states; it is never decorative
  when no load is in progress.

### Data contract for row metadata

- **D-07:** Treat `created_by` preload as a hard contract for primary thread-list
  behavior. Keep/add tests that fail when expected `created_by.handle` is missing.
- **D-08:** Keep existing defensive rendering fallback behavior only as safety, not as
  license to skip preload guarantees.

### State-shape contract

- **D-09:** Add public `init_screen_state/1` for `thread_list` and replace inline
  `%{selected_index: 0}` defaults with initializer-backed state reads.
- **D-10:** ThreadList is not intentionally stateless; it owns
  `state.screen_state[:thread_list]` selection state.

### Locked inherited behavior

- **D-11:** Keep the two-pass sticky-then-recency sort behavior (sticky bucket first,
  recency within buckets) as a load-bearing inherited decision.
- **D-12:** Keep `SelectionList` + `ListRow` row rendering pattern unchanged.

### the agent's Discretion

- Exact spinner widget variant (`Widgets.Progress.Spinner` vs another valid in-tree
  progress primitive) as long as it remains indeterminate and low-density.
- Exact helper naming for thread-list screen-state accessors beyond required
  `init_screen_state/1`.
- Exact section-order edits required for `AUDIT-18` compliance.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase requirements and rubric

- `.planning/workstreams/phase-03-screen-audit/ROADMAP.md` — Phase 6 goal and success criteria.
- `.planning/workstreams/phase-03-screen-audit/REQUIREMENTS.md` — `THREADS-01..07` and inherited `AUDIT-05..22` with emphasis on `AUDIT-10`, `AUDIT-12`, `AUDIT-17`, `AUDIT-18`, `AUDIT-19`.
- `.planning/workstreams/phase-03-screen-audit/STATE.md` — locked-decision continuity and current sequencing.

### Workstream research

- `.planning/workstreams/phase-03-screen-audit/research/ARCHITECTURE.md` — ThreadList architecture findings, correctness risks, and reserved layout-region guidance.
- `.planning/workstreams/phase-03-screen-audit/research/PITFALLS.md` — anti-affordance and preserved-behavior traps for ThreadList.
- `.planning/workstreams/phase-03-screen-audit/research/SUMMARY.md` — phase-level recommendations and dependency order.

### Prior context this phase inherits

- `.planning/workstreams/phase-03-screen-audit/phases/00-cross-cutting-extractions-prelude/00-CONTEXT.md` — helper-contract decisions consumed by ThreadList.
- `.planning/workstreams/phase-03-screen-audit/phases/05-boardlist/05-CONTEXT.md` — sibling list-screen decisions for dead-code posture and loading affordance consistency.

### Code to read before planning

- `lib/foglet_bbs/tui/screens/thread_list.ex` — audited target screen.
- `lib/foglet_bbs/tui/app.ex` — production owner of `{:load_threads, board_id}` async loading flow.
- `test/foglet_bbs/tui/screens/thread_list_test.exs` — coverage for arity dispatch, sorting, and metadata contract.
- `lib/foglet_bbs/tui/widgets/list/selection_list.ex` — list interaction primitive.
- `lib/foglet_bbs/tui/widgets/list/list_row.ex` — row rendering primitive.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable assets

- `Theme.from_state/1` and `Screens.Domain.get/2` are already available for ThreadList.
- `SelectionList.render/3` + `ListRow.render_with_metadata/6` already satisfy intended row UX.
- `ScreenFrame.render/4` already provides stable chrome and key hints.

### Established patterns

- Production thread loading is owned by `App.do_update({:load_threads, board_id}, state)`.
- `ThreadList.load_threads/2` exists and is currently used by tests as a seam.
- `thread_list` selection state currently uses inline `%{selected_index: 0}` defaults,
  which is the direct AUDIT-19 normalization target.

### Integration points

- Enter from BoardList via `{:load_threads, board.id}`.
- Open thread dispatches `{:load_posts, thread.id}` and transitions to `:post_reader`.
- Compose shortcut routes to NewThread with `origin: :thread_list`; this path must remain unchanged.

</code_context>

<specifics>
## Specific Ideas

- User selected spinner loading affordance for ThreadList rather than plain text fallback policy.
- Strict preload guarantee for `created_by` should be enforced by tests, not left implicit.
- Correctness fix (`Code.ensure_loaded/1`) is a non-negotiable patch in this phase.

</specifics>

<deferred>
## Deferred Ideas

- Thread-row mention highlighting, chat indicators, and moderator tags remain deferred to the milestones that own those features (protected layout region).
- Any two-pane or tree-style thread navigation is deferred and out of scope.

</deferred>

---

*Phase: 06-threadlist*
*Context gathered: 2026-04-21*
