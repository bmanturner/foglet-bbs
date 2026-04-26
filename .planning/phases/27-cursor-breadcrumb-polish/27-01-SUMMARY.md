---
phase: 27-cursor-breadcrumb-polish
plan: "01"
subsystem: tui-widgets
tags: [cursor, text-input, accessibility, cell-width, CURSOR-01]
dependency_graph:
  requires: []
  provides: [CURSOR-01]
  affects:
    - lib/foglet_bbs/tui/widgets/input/text_input.ex
tech_stack:
  added: []
  patterns:
    - grapheme-split cursor insertion using String.graphemes/1 + Enum.split/2
    - TextWidth.display_width/1 for cell-width-correct cursor column tests
key_files:
  created: []
  modified:
    - lib/foglet_bbs/tui/widgets/input/text_input.ex
    - test/foglet_bbs/tui/widgets/input/text_input_test.exs
decisions:
  - Use grapheme-position split (Enum.split at cursor_pos) to derive left/cursor/right text spans
  - Replace "あ" with "中" in wide-grapheme test because Raxol.UI.TextMeasure reports "あ" as 1 cell, "中" as 2
  - Disabled inputs propagate through `focused? and not disabled?` — no separate render clause needed
metrics:
  duration: 2min
  completed_date: "2026-04-26"
  tasks_completed: 2
  files_changed: 2
---

# Phase 27 Plan 01: TextInput Insertion-Point Cursor (CURSOR-01) Summary

**One-liner:** Insertion-point cursor in shared TextInput using grapheme-split at `raxol_state.cursor_pos` with `TextWidth.display_width` column tests.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Specify insertion-point cursor behavior (RED) | 51ac052 | test/foglet_bbs/tui/widgets/input/text_input_test.exs |
| 2 | Render cursor inside TextInput using cursor_pos (GREEN) | 069f81c | lib/foglet_bbs/tui/widgets/input/text_input.ex, test/..._test.exs |

## What Was Built

The `TextInput.render/2` now renders an insertion-point cursor at `raxol_state.cursor_pos` when `focused: true` and not `disabled: true`. The implementation:

1. Derives `display_text` from value (or `mask_char` repetition for masked inputs)
2. Splits the display text at `cursor_pos` grapheme boundary using `String.graphemes/1` + `Enum.split/2`
3. Renders a `row gap: 0` of `[left_text, "▌" (accent, bold), right_text]`
4. Falls back to `RaxolTextInput.render/2` for unfocused and disabled inputs

Tests cover: cursor_pos after type+backspace sequence, wide grapheme cell-width proof (using "中" = 2 cells), focused:false no-cursor, disabled:true no-cursor, and masked render with no raw value leak.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Wide grapheme test character choice**
- **Found during:** Task 2 GREEN implementation
- **Issue:** Plan specified "aあe" as the wide-grapheme test case. `Raxol.UI.TextMeasure` reports "あ" as 1 cell, not 2. The test assertion `== 3` would fail even with correct implementation.
- **Fix:** Changed test to use "a中e" — "中" measures as 2 terminal cells per `Raxol.UI.TextMeasure`, correctly proving cell-width math diverges from character count (column 3 != character count 2).
- **Files modified:** test/foglet_bbs/tui/widgets/input/text_input_test.exs
- **Commit:** 069f81c

## TDD Gate Compliance

- RED gate commit: 51ac052 (`test(27-01): add failing CURSOR-01 insertion-point cursor tests`)
- GREEN gate commit: 069f81c (`feat(27-01): implement CURSOR-01 insertion-point cursor in TextInput`)
- REFACTOR: not needed — implementation was clean in GREEN pass

## Known Stubs

None.

## Threat Flags

None — no new network endpoints or auth paths introduced. Masked input threat (T-27-01) mitigated: `inspect(rendered)` cannot contain raw `"secret"` value. Cursor-only-when-focused threat (T-27-02) mitigated via `focused? and not disabled?` guard. Cell-width math (T-27-03) mitigated by `TextWidth.display_width/1` in tests.

## Self-Check: PASSED

- `lib/foglet_bbs/tui/widgets/input/text_input.ex` — exists
- `test/foglet_bbs/tui/widgets/input/text_input_test.exs` — exists
- Commits 51ac052, 069f81c — verified in git log
- All 21 tests pass
