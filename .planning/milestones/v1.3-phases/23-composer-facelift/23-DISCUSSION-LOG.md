# Phase 23: composer-facelift - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the analysis.

**Date:** 2026-04-25
**Phase:** 23-composer-facelift
**Mode:** assumptions
**Areas analyzed:** Shared Composer Shell, Mode Control, Character Budgets, Context Collapse, Preview Path, Behavior Preservation, Test Placement

## Assumptions Presented

### Shared Composer Shell

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Create `Foglet.TUI.Widgets.Composer.EditorFrame` or equivalent as the shared composer widget boundary, wrapping existing body editor rendering rather than replacing `MultiLineInput`. | Confident | `.planning/phases/23-composer-facelift/23-SPEC.md`; `SCREENS.md` §New Thread And Post Composer; `lib/foglet_bbs/tui/widgets/compose.ex`; `lib/foglet_bbs/tui/screens/post_composer.ex`; `lib/foglet_bbs/tui/screens/new_thread.ex` |
| Keep `TextInput` for title editing and `MultiLineInput` for body editing. | Confident | `.planning/phases/23-composer-facelift/23-SPEC.md` requirements 2 and 7; `lib/foglet_bbs/tui/screens/new_thread.ex`; `lib/foglet_bbs/tui/screens/new_thread/state.ex`; `lib/foglet_bbs/tui/screens/post_composer/state.ex` |

### Mode Control

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Render Edit/Preview as a compact in-shell segmented row, not only as key hints and not necessarily as stateful `Input.Tabs`. | Likely | `.planning/phases/23-composer-facelift/23-SPEC.md` requirement 3; `SCREENS.md` proposed edit/preview layout; current `PostComposer.handle_key/2` and `NewThread.handle_key/2` already own Tab behavior |

### Character Budgets

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Use text-first counters with normal/warning/error theme slots; progress segments are optional polish. | Confident | `.planning/phases/23-composer-facelift/23-SPEC.md` requirement 4 and boundaries; `SCREENS.md` character counter theme notes; `lib/foglet_bbs/tui/presentation.ex`; `lib/foglet_bbs/tui/widgets/display/progress.ex` |
| Keep counters as character-count policy limits, not display-width limits. | Confident | `.planning/phases/16-unicode-width-foundation/16-CONTEXT.md` D-07/D-08; current `String.length/1` enforcement in `PostComposer` and `NewThread` |

### Context Collapse

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| At 64x22, quote/board/title context collapses before the mode row, editor body, and compact counter. | Confident after user clarification | `.planning/phases/23-composer-facelift/23-SPEC.md` requirement 5; user confirmed "Keep it" after clarification |

### Preview Path

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Preview stays in the same shell and uses existing `Post.MarkdownBody`, not a new `PostCard`-based final-post mock. | Confident | `.planning/phases/23-composer-facelift/23-SPEC.md` requirement 6 and out-of-scope list; current `PostComposer` and `NewThread` preview paths |

### Behavior Preservation

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Keep existing key handling, validation, domain calls, and transition behavior intact. | Confident | `.planning/phases/23-composer-facelift/23-SPEC.md` requirement 7; `test/foglet_bbs/tui/screens/post_composer_test.exs`; `test/foglet_bbs/tui/screens/new_thread_test.exs`; `test/foglet_bbs/tui/app_test.exs` |

### Test Placement

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Add a mirrored composer widget test, extend existing screen behavior tests, and extend `layout_smoke_test.exs` at the standard v1.3 size triple. | Confident | `lib/foglet_bbs/tui/widgets/README.md`; `.planning/phases/20-rich-rows-and-thread-flow/20-CONTEXT.md`; `.planning/phases/22-post-reader-facelift/22-CONTEXT.md`; `test/foglet_bbs/tui/layout_smoke_test.exs` |

## Corrections Made

No corrections changed the decisions. The user asked for clarification on the context-collapse assumption; after explanation, they confirmed keeping it.

