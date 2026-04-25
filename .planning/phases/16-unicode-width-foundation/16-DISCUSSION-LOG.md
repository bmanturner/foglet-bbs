# Phase 16: unicode-width-foundation - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the analysis.

**Date:** 2026-04-25
**Phase:** 16-unicode-width-foundation
**Mode:** assumptions
**Areas analyzed:** Text Width API, Migration Scope, Character Count Boundaries, Test Strategy

## Assumptions Presented

### Text Width API

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Phase 16 should add a thin Foglet-owned `TextWidth` helper under the TUI namespace, delegating measurement and splitting to `Raxol.UI.TextMeasure`, while adding Foglet convenience functions for truncation and padding. | Confident | `.planning/phases/16-unicode-width-foundation/16-SPEC.md`; `vendor/raxol/lib/raxol/ui/text_measure.ex`; `docs/raxol/core/ARCHITECTURE.md`; `SCREENS.md` |

### Migration Scope

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| The must-migrate Phase 16 paths are `ListRow.render_with_metadata/6`, existing `Chrome.KeyBar`, `Modal.word_wrap/2`, reusable clipping/truncation helpers such as `MainMenu.clip/2`, and composer cursor insertion in `Compose.render_input/4`; broader account/sysop/moderation paths should only be touched if they can use the new helper cheaply or need documentation as character-count/non-foundation work. | Confident | `.planning/phases/16-unicode-width-foundation/16-SPEC.md`; `lib/foglet_bbs/tui/widgets/list/list_row.ex`; `lib/foglet_bbs/tui/widgets/modal.ex`; `lib/foglet_bbs/tui/widgets/compose.ex`; `lib/foglet_bbs/tui/screens/main_menu.ex`; `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex` |

### Character Count Boundaries

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Post/title length counters and enforcement remain character-count policies using existing string-length behavior, with comments/tests documenting that they are not terminal display-width limits. | Confident | `.planning/phases/16-unicode-width-foundation/16-SPEC.md`; `lib/foglet_bbs/tui/screens/post_composer.ex`; `lib/foglet_bbs/tui/screens/new_thread.ex`; `test/foglet_bbs/tui/screens/post_composer_test.exs`; `test/foglet_bbs/tui/screens/new_thread_test.exs` |

### Test Strategy

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Tests should add helper-level width cases plus focused widget/layout assertions that measure flattened output by display width, preserving current ASCII assertions where practical and adding representative 64x22, 80x24, and wide/tall contracts. | Likely | `test/foglet_bbs/tui/widgets/list/list_row_test.exs`; `test/foglet_bbs/tui/widgets/modal_test.exs`; `test/foglet_bbs/tui/layout_smoke_test.exs`; `.planning/phases/16-unicode-width-foundation/16-SPEC.md` |

## Corrections Made

No corrections — all assumptions confirmed.

## External Research

No external research was performed. The only flagged topic was terminal-dependent ambiguous-width behavior for `●`, `◆`, `▸`, `▾`, `✓`, and `×`; the confirmed decision is to lock Phase 16 to Raxol's current width model rather than expanding scope into terminal/font compatibility research.
