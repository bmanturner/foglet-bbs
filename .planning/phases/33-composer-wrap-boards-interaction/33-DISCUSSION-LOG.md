# Phase 33: Composer Wrap & Boards Interaction - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md - this log preserves the analysis.

**Date:** 2026-04-28
**Phase:** 33-composer-wrap-boards-interaction
**Mode:** assumptions
**Areas analyzed:** Composer visual wrap, Composer width and cursor behavior, Boards Enter toggle, Verification and tests

## Assumptions Presented

### Composer Visual Wrap

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Implement visual soft-wrap in `Foglet.TUI.Widgets.Compose.render_input/4` using `Foglet.TUI.TextWidth.wrap/2`, keeping `MultiLineInput.value` unchanged and leaving submit paths untouched. | Confident | `lib/foglet_bbs/tui/widgets/compose.ex`; `lib/foglet_bbs/tui/screens/post_composer.ex`; `lib/foglet_bbs/tui/screens/new_thread.ex`; `lib/foglet_bbs/tui/text_width.ex`; `.planning/phases/33-composer-wrap-boards-interaction/33-SPEC.md` |

### Composer Width And Cursor Behavior

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Reflow from current terminal/editor width during render and update or pass width from `PostComposer`/`NewThread`, rather than hard-wrapping in state. | Confident | `lib/foglet_bbs/tui/screens/post_composer/state.ex`; `lib/foglet_bbs/tui/screens/new_thread/state.ex`; `.planning/phases/33-composer-wrap-boards-interaction/33-SPEC.md` |
| Preserve existing logical cursor/input handling and add only enough visual cursor placement for wrapped rows; do not introduce a new editor state model. | Likely | `lib/foglet_bbs/tui/widgets/compose.ex`; `Raxol.UI.Components.Input.MultiLineInput` usage in composer state modules |

### Boards Enter Toggle

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Change `BoardList.handle_key(:enter)` so category Enter persists the updated `BoardTree` state and returns an update with no commands, while board leaf Enter continues navigating. | Confident | `lib/foglet_bbs/tui/screens/board_list.ex`; `lib/foglet_bbs/tui/widgets/list/board_tree.ex`; `lib/foglet_bbs/tui/widgets/display/tree.ex`; `test/foglet_bbs/tui/screens/board_list_test.exs` |
| Keep board expand/collapse UI-local, with no context calls or DB writes. | Confident | `.planning/phases/33-composer-wrap-boards-interaction/33-SPEC.md`; `lib/foglet_bbs/tui/screens/board_list/state.ex`; `lib/foglet_bbs/tui/widgets/list/board_tree.ex` |

### Verification And Tests

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Add focused tests for shared composer wrapping, both consuming composer screens, resize/logical-buffer preservation, category Enter toggling, no category commands, and board-leaf Enter regression. | Confident | `test/foglet_bbs/tui/screens/post_composer_test.exs`; `test/foglet_bbs/tui/screens/new_thread_test.exs`; `test/foglet_bbs/tui/screens/board_list_test.exs`; `.planning/phases/33-composer-wrap-boards-interaction/33-SPEC.md` |

## Corrections Made

No corrections - all assumptions confirmed.

## External Research

No external research was needed. Phase 33 is fully constrained by local SPEC, existing `TextWidth` helper behavior, composer source, and tree widget behavior.
