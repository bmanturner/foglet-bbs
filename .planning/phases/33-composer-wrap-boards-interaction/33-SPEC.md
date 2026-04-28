# Phase 33: Composer Wrap & Boards Interaction - Specification

**Created:** 2026-04-28
**Ambiguity score:** 0.13 (gate: <= 0.20)
**Requirements:** 5 locked

## Goal

The new-thread and reply composers visually soft-wrap overlong editor lines without changing submitted text, and the Boards screen toggles focused category expansion with Enter while preserving board-leaf navigation.

## Background

Phase 26 added `Foglet.TUI.TextWidth.wrap/2` and existing terminal-width helpers, and the Boards screen already renders a width-aware `BoardTree` with visible `▾` expanded and `▸` collapsed category indicators. `Foglet.TUI.Screens.PostComposer` and `Foglet.TUI.Screens.NewThread` both use `Raxol.UI.Components.Input.MultiLineInput`, but they initialize body editors with `wrap: :none`, and `Foglet.TUI.Widgets.Compose.render_input/4` currently renders `input_st.value` split only on real newline characters. That means long logical lines do not visually wrap in Foglet-owned rendering.

The Boards screen already delegates Up/Down/Left/Right to `BoardTree`, and Enter on a focused board leaf navigates to `:thread_list` and dispatches `{:load_threads, board.id}`. Enter on a focused category currently produces no screen update because `BoardList.handle_key/2` only treats `:node_activated` on a board leaf as actionable.

## Requirements

1. **Reply composer visual wrap**: The reply post composer renders overlong logical body lines as multiple visual rows within the editor width.
   - Current: `PostComposer` body edit mode renders `input_st.value` split only on real newline boundaries, so a long line remains one text row.
   - Target: `PostComposer` edit mode visually wraps long logical lines using `TextWidth.wrap/2` or an equivalent Raxol-backed path that honors terminal display width.
   - Acceptance: A reply draft containing one overlong line renders as at least two visible editor text rows at a compact editor width, while the underlying `input_state.value` remains the original one-line string.

2. **New-thread composer visual wrap**: The new-thread compose step renders overlong logical body lines as multiple visual rows within the editor width.
   - Current: `NewThread` body edit mode delegates to the same shared `Compose.render_input/4` path and does not visually wrap overlong logical lines.
   - Target: `NewThread` compose step visually wraps long body lines with the same behavior as the reply composer.
   - Acceptance: A new-thread body draft containing one overlong line renders as at least two visible editor text rows at a compact editor width, while the title field behavior is unchanged.

3. **Logical buffer preservation**: Visual wrapping never inserts newline characters into submitted post text and reflows when terminal width changes.
   - Current: Composer state stores the submitted body in `MultiLineInput.value`, but no visual-wrap behavior exists to verify that render-only wrapping leaves the value unchanged.
   - Target: Wrapping is a render concern only; user-entered newlines remain the only newline characters in the editor value, and a resize from 80x24 to 64x22 changes only the rendered visual rows.
   - Acceptance: After typing or seeding a long single-line body and rendering at both 80x24 and 64x22, the stored/submitted body string is byte-equivalent before and after render; the narrower render produces additional visual rows.

4. **Category Enter toggles expansion**: Pressing Enter on a focused Boards-screen category toggles that category between expanded and collapsed states.
   - Current: Left and Right can collapse or expand categories through `BoardTree`, but Enter on a focused category is ignored by `BoardList.handle_key/2`.
   - Target: Enter on a focused category updates the screen-local `BoardTree` expansion state and refreshes the visible category indicator (`▾`/`▸` or equivalent).
   - Acceptance: With focus on a category at 64x22, pressing Enter once hides that category's board children and shows the collapsed indicator; pressing Enter again shows the children and expanded indicator.

5. **Board leaf Enter regression guard**: Enter on a focused board leaf continues to navigate to that board's thread list, and category toggling performs no domain mutation.
   - Current: Board leaf Enter navigation exists and dispatches `{:load_threads, board.id}`; category Enter currently produces no action.
   - Target: Board leaf Enter behavior is unchanged, and category Enter changes only UI-local `BoardTree` state.
   - Acceptance: Focused board Enter sets `current_screen: :thread_list`, sets `current_board`, and returns exactly one load-threads command; focused category Enter returns no subscribe/unsubscribe/thread/domain commands and causes no database writes.

## Boundaries

**In scope:**
- Visual soft-wrap for body edit mode in `PostComposer`.
- Visual soft-wrap for body edit mode in `NewThread`.
- Preservation of logical editor values and submitted body text.
- Render reflow behavior across 80x24 and 64x22 terminal sizes.
- Enter-to-toggle category expansion on the Boards screen using screen-local tree state.
- Regression tests for board-leaf Enter navigation and no domain command from category Enter.

**Out of scope:**
- Hard-wrap-on-submit or automatic insertion of real newlines - deferred as `POST-FUT-01`.
- Replacing the composer editor with a new full-screen editing model - this phase is stabilization, not a composer redesign.
- Persisting per-user Boards expansion state across sessions - deferred as `BOARD-FUT-01`; this phase keeps expansion UI-local.
- Browser workflows or web UI for composing posts or browsing boards - Foglet remains SSH/TUI-first for v1.x.
- Changing post validation limits, markdown preview semantics, or thread creation authorization - existing contexts already own those contracts.
- Alternative keybind schemes beyond existing terminal conventions - this phase only adds Enter parity with existing Left/Right category controls.

## Constraints

- Use `Foglet.TUI.TextWidth.wrap/2` or a Raxol-provided equivalent only if it preserves `MultiLineInput.value` as the logical buffer.
- Keep body wrapping display-width aware and compatible with the 64x22 minimum terminal.
- Do not introduce database persistence or new domain context calls for Boards expand/collapse.
- Keep render functions pure over already-loaded state; no Repo, PubSub, or command dispatch from composer rendering or category toggling.
- Preserve current board-leaf Enter command shape so downstream thread-list loading remains unchanged.

## Acceptance Criteria

- [ ] `PostComposer` edit mode renders one overlong logical body line as multiple visible rows at compact width.
- [ ] `NewThread` compose body edit mode renders one overlong logical body line as multiple visible rows at compact width.
- [ ] Rendering or resizing composer screens from 80x24 to 64x22 does not change the stored body string or insert newline characters.
- [ ] Composer submission sends the logical body text, not the visually wrapped text.
- [ ] Boards category Enter toggles collapsed and expanded states and updates the visible `▸`/`▾` indicator.
- [ ] Boards board-leaf Enter still navigates to `:thread_list` and returns `{:load_threads, board.id}`.
- [ ] Boards category Enter returns no domain mutation commands and performs no database writes.

## Ambiguity Report

| Dimension          | Score | Min   | Status | Notes |
|--------------------|-------|-------|--------|-------|
| Goal Clarity       | 0.92  | 0.75  | OK     | Both roadmap requirements locked as phase deliverables. |
| Boundary Clarity   | 0.90  | 0.70  | OK     | Persistence, hard-wrap, web UI, and redesign work excluded. |
| Constraint Clarity | 0.80  | 0.65  | OK     | Logical-buffer preservation and UI-local Boards state are explicit. |
| Acceptance Criteria| 0.86  | 0.70  | OK     | Pass/fail checks cover render, submit, resize, toggle, and navigation. |
| **Ambiguity**      | 0.13  | <=0.20| OK     | Gate passed after round 1. |

Status: OK = met minimum, WARN = below minimum (planner treats as assumption)

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | Should Phase 33 deliver both roadmap fixes or prioritize one? | Deliver both POST-02 and BOARD-01. |
| 1 | Researcher | Should composer wrap be visual-only or allowed to use Raxol internals? | Visual-only is locked; a Raxol tool is acceptable only if it preserves logical submitted text. |
| 1 | Researcher | Should Boards category expansion persist? | Expansion state remains session-local/UI-local; no persistence in this phase. |

---

*Phase: 33-composer-wrap-boards-interaction*
*Spec created: 2026-04-28*
*Next step: $gsd-discuss-phase 33 - implementation decisions (how to build what's specified above)*
