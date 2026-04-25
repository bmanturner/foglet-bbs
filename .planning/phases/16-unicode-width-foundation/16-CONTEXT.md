# Phase 16: unicode-width-foundation - Context

**Gathered:** 2026-04-25 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 16 establishes Foglet-owned Unicode display-width infrastructure before glyph-heavy TUI facelift work ships. It adds one shared TUI helper for terminal-cell measurement, truncation, padding, and display-width splitting/slicing; migrates the highest-risk current layout-sensitive row, chrome/footer, modal, reusable clipping/truncation, and composer cursor paths; and proves ASCII, accented Latin, combining mark, CJK, and milestone glyph behavior without changing storage, validation, domain, browser, or visual facelift scope.
</domain>

<decisions>
## Implementation Decisions

### Text Width API
- **D-01:** Add `Foglet.TUI.TextWidth` under the TUI namespace as the shared Foglet API for terminal display-width behavior.
- **D-02:** Delegate measurement and display-width splitting to `Raxol.UI.TextMeasure`; do not invent an independent width policy unless tests prove Raxol cannot satisfy the locked Phase 16 cases.
- **D-03:** Add Foglet convenience functions for display width, ellipsis truncation, left/right padding, and display-width splitting or slicing so local TUI code does not call Raxol primitives directly in every widget.

### Migration Scope
- **D-04:** Must migrate `ListRow.render_with_metadata/6`, existing `Chrome.KeyBar`, `Modal.word_wrap/2`, reusable clipping/truncation helpers such as main-menu clipping, and composer cursor insertion in `Compose.render_input/4`.
- **D-05:** Keep the phase focused on current foundation paths. Broader Account, Sysop, Moderation, and other screen string operations should only migrate where cheap through the new helper or be documented as character-count/non-layout-sensitive paths.
- **D-06:** Do not start Chrome V2, theme/mode contracts, rich row redesign, board/post/composer facelifts, browser UI, or domain behavior changes in this phase.

### Character Count Boundaries
- **D-07:** Post body length, thread title length, verification-code length, and similar product validation rules remain character-count policies, not terminal display-width limits.
- **D-08:** Existing `String.length/1` and `String.slice/3` usage may remain in character-count enforcement paths when documented and tested as intentionally separate from terminal layout width.

### Test Strategy
- **D-09:** Add helper-level tests covering ASCII, accented Latin, combining marks, CJK, and the milestone glyph set `●`, `◆`, `▸`, `▾`, `✓`, `×`.
- **D-10:** Convert or add focused widget tests that measure flattened rendered output by `Foglet.TUI.TextWidth.display_width/1`, while preserving existing ASCII layout assertions where practical.
- **D-11:** Add representative size-contract coverage for 64x22, 80x24, and at least one wide/tall terminal across row, chrome/footer, modal, and composer paths.
- **D-12:** Lock Phase 16 behavior to Raxol's current width model for the milestone glyph set; do not expand scope into terminal/font compatibility research.

### the agent's Discretion
- Exact helper function names, arities, and internal implementation details are planner discretion as long as the shared API clearly covers measurement, truncation, padding, and display-width splitting/slicing.
- Exact structure of the source-level scan or equivalent focused test is planner discretion, but it must prove migrated layout-sensitive paths no longer use direct grapheme-count string operations for terminal layout width.

### Folded Todos
None.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Requirements
- `.planning/phases/16-unicode-width-foundation/16-SPEC.md` — Locked Phase 16 requirements, boundaries, constraints, acceptance criteria, and interview decisions.
- `.planning/ROADMAP.md` §Phase 16 — Milestone position, dependency, requirements, and success criteria.
- `.planning/REQUIREMENTS.md` §Unicode Width Foundation — Requirement IDs `WIDTH-01` through `WIDTH-05`.
- `SCREENS.md` §Unicode Width Hardening Checklist — v1.3 design rationale and width-sensitive target paths.

### Raxol Width Model
- `vendor/raxol/lib/raxol/ui/text_measure.ex` — Existing Raxol display-width facade to wrap.
- `docs/raxol/core/ARCHITECTURE.md` — Raxol render/layout architecture and Unicode width source-of-truth notes.

### TUI Widget Conventions
- `lib/foglet_bbs/tui/widgets/README.md` — Widget organization and ownership.
- `docs/raxol/getting-started/WIDGET_GALLERY.md` — Raxol widget conventions for TUI work.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Raxol.UI.TextMeasure` already provides `display_width/1`, `char_display_width/1`, and `split_at_display_width/2`; `Foglet.TUI.TextWidth` should wrap this rather than duplicate Unicode tables.
- `test/foglet_bbs/tui/widgets/list/list_row_test.exs` already has flattening helpers for rendered widget trees and ASCII row-width assertions that can be adapted to display-width assertions.
- `test/foglet_bbs/tui/layout_smoke_test.exs` already exercises rendered TUI layouts and is a natural home for representative terminal-size checks.

### Established Patterns
- TUI widgets live under `lib/foglet_bbs/tui/widgets/`; cross-cutting TUI helpers belong under `lib/foglet_bbs/tui/`.
- Render functions should stay pure over already-loaded state and route styling through `Foglet.TUI.Theme`.
- Tests mirror `lib/` paths under `test/foglet_bbs/`, with pure widget/screen tests using `ExUnit.Case`.
- Existing tests often flatten Raxol view trees before asserting content; Phase 16 should update those assertions to terminal display width where layout width matters.

### Integration Points
- `lib/foglet_bbs/tui/widgets/list/list_row.ex` currently computes row width with `String.length/1` and truncates titles with `String.slice/3`.
- `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex` currently renders key hints without a width-aware truncation contract.
- `lib/foglet_bbs/tui/widgets/modal.ex` currently wraps modal text using `String.length/1`.
- `lib/foglet_bbs/tui/widgets/compose.ex` currently inserts the cursor with `String.split_at/2`.
- `lib/foglet_bbs/tui/screens/post_composer.ex` and `lib/foglet_bbs/tui/screens/new_thread.ex` intentionally use character-count semantics for content limits and counters.
- `lib/foglet_bbs/tui/screens/main_menu.ex` contains reusable clipping/truncation behavior that should move to or use the shared helper where it is terminal-layout-sensitive.
</code_context>

<specifics>
## Specific Ideas

- Keep the helper thin and boring: a Foglet contract over Raxol's display-width behavior plus convenience operations local widgets need.
- Treat `●`, `◆`, `▸`, `▾`, `✓`, and `×` as required regression fixtures against Raxol's current width model, not as a prompt to solve terminal/font variance.
</specifics>

<deferred>
## Deferred Ideas

None — analysis stayed within phase scope.

### Reviewed Todos (not folded)
None.
</deferred>

---

*Phase: 16-unicode-width-foundation*
*Context gathered: 2026-04-25*
