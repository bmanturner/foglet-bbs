# Phase 16: Unicode Width Foundation - Specification

**Created:** 2026-04-25
**Ambiguity score:** 0.12 (gate: <= 0.20)
**Requirements:** 5 locked

## Goal

Foglet TUI layout-sensitive text paths measure, truncate, pad, and cursor-position terminal text by display width through one shared helper before Unicode-heavy facelift screens ship.

## Background

`SCREENS.md` chooses a UTF-8 terminal UI direction and explicitly warns that Unicode-heavy aligned layouts must harden display-width calculations first. Raxol already exposes `Raxol.UI.TextMeasure.display_width/1`, `char_display_width/1`, and `split_at_display_width/2`, and some vendored Raxol layout/rendering paths already use it. Foglet's local TUI layer still has multiple layout-sensitive `String.length/1`, `String.slice/2`, `String.slice/3`, and `String.pad_*` assumptions in rows, modal wrapping, composer rendering, counters, form editing, and screen truncation.

Phase 16 is the foundation phase for v1.3. It does not facelift screens. It establishes a Foglet-owned width helper and proves the highest-risk current TUI paths can survive ASCII, accented Latin, combining marks, CJK, and the milestone glyph set without regressing existing ASCII-heavy behavior.

## Requirements

1. **Shared TextWidth helper**: Foglet exposes one TUI display-width helper for measurement, truncation, padding, and display-width splitting/slicing.
   - Current: Foglet local TUI code calls `String.length/1`, `String.slice/2`, `String.slice/3`, and `String.pad_*` directly in layout-sensitive paths, while Raxol has `Raxol.UI.TextMeasure` but no Foglet wrapper contract.
   - Target: A Foglet-owned TUI helper wraps the Raxol display-width primitive and provides named functions for display width, truncation with ellipsis, right/left padding, and splitting or slicing by terminal cell width.
   - Acceptance: Unit tests prove the helper returns expected widths and outputs for ASCII, accented Latin, combining marks, CJK, and `●`, `◆`, `▸`, `▾`, `✓`, `×`.

2. **Aligned row hardening**: Existing aligned row rendering uses the shared helper for title/metadata layout instead of grapheme counts.
   - Current: `Foglet.TUI.Widgets.List.ListRow.render_with_metadata/6` uses `String.length/1` and `String.slice/3`, so CJK, combining marks, and planned glyph markers can misalign rows or truncate at the wrong visible column.
   - Target: The row title, marker, metadata, ellipsis, and padding math use the shared display-width helper while preserving the existing metadata-priority behavior.
   - Acceptance: Row tests prove rendered flat text occupies the requested terminal width for ASCII, accented Latin, combining marks, CJK, and milestone glyph inputs, and preserves current ASCII cases at widths already covered by tests.

3. **Chrome and clipping path inventory**: The existing command-footer/chrome and screen clipping or truncation paths that are layout-sensitive are either migrated to the shared helper or explicitly documented as non-layout-sensitive.
   - Current: `Chrome.KeyBar`, modal text wrapping, moderation truncation, sysop snapshot padding, and similar display paths contain direct string-width assumptions or no width contract.
   - Target: Phase 16 identifies the current layout-sensitive TUI paths and migrates the paths needed by v1.3 foundations: existing command-footer/chrome key hint output, modal wrapping, and reusable screen truncation helpers.
   - Acceptance: A source-level scan or focused tests show no remaining direct `String.length/1`, `String.slice/2`, `String.slice/3`, or `String.pad_*` calls in the migrated layout-sensitive helper/row/chrome/modal paths except where documented as character-count limits rather than terminal display width.

4. **Composer cursor and input display baseline**: Composer display paths have width-aware cursor rendering and counting where visible terminal columns matter, without changing storage or validation semantics.
   - Current: `Foglet.TUI.Widgets.Compose.render_input/4` inserts the cursor using `String.split_at/2` with Raxol cursor positions, and composer screens display character budgets with `String.length/1`.
   - Target: Cursor display and any visible editor-width calculations use the shared helper for terminal columns; character budgets that are intentionally character limits remain documented and tested as character counts.
   - Acceptance: Composer/widget tests prove cursor rendering remains correct for ASCII and does not split or visually misplace CJK, combining mark, or milestone glyph input; existing `max_post_length` character-limit behavior remains unchanged.

5. **Responsive size-contract tests**: Width foundation coverage includes representative render checks at the v1.3 size contracts.
   - Current: Existing tests cover many widget behaviors, but Phase 16 has no dedicated contract proving width-safe rendering at 64x22, 80x24, and a wide/tall terminal size.
   - Target: Focused tests exercise representative row, chrome/footer, modal, and composer paths at 64x22, 80x24, and at least one wide/tall size.
   - Acceptance: Tests pass for the three size classes and prove no representative output line exceeds its intended terminal width when using the shared helper.

## Boundaries

**In scope:**
- Add a Foglet TUI display-width helper that delegates to Raxol's Unicode-aware measurement.
- Harden layout-sensitive row alignment, command-footer/chrome key hints, modal wrapping, reusable truncation/clipping, and composer cursor display paths.
- Add tests for ASCII, accented Latin, combining marks, CJK, and the SCREENS.md glyph set: `●`, `◆`, `▸`, `▾`, `✓`, `×`.
- Add representative size-contract tests for 64x22, 80x24, and one wide/tall terminal.
- Preserve existing ASCII-heavy screen behavior and current domain/input validation semantics.
- Document any remaining direct string operations that are intentionally character-count limits rather than terminal layout width.

**Out of scope:**
- Chrome V2 breadcrumbs, grouped command bars, or mode-aware status atoms - Phase 18 owns Chrome V2.
- Theme slot additions or screen mode metadata - Phase 17 owns those contracts.
- Rich row visual redesign, board tree facelift, post reader facelift, or composer editor-frame facelift - later v1.3 phases own those changes.
- Changing database schemas, contexts, authorization, SSH authentication, or browser workflows - Phase 16 is TUI rendering infrastructure only.
- Rewriting vendored Raxol internals broadly - Phase 16 may rely on Raxol's existing text measurement but should keep Foglet changes scoped to Foglet-owned TUI paths unless a narrow compatibility fix is required.
- Changing `max_post_length` or other character-count validation rules into display-width limits - this phase separates terminal display width from content policy limits.

## Constraints

- Foglet remains SSH-first; do not add browser UI or end-user Phoenix workflows.
- New TUI code must route styling through existing theme conventions and keep render functions pure over already-loaded state.
- Use the existing Raxol text-measurement primitive as the display-width source of truth unless tests prove it cannot satisfy the required cases.
- The hard minimum terminal size is 64x22, the compact target is 80x24, and at least one wide/tall size must be represented in tests.
- ASCII-heavy existing screens must retain their current layout behavior.
- Character-count limits, such as post length policy, remain character-count limits unless a later phase explicitly changes product requirements.

## Acceptance Criteria

- [ ] A Foglet TUI TextWidth helper exists and is the shared API for display width, truncation, padding, and display-width splitting/slicing.
- [ ] TextWidth tests cover ASCII, accented Latin, combining marks, CJK, and `●`, `◆`, `▸`, `▾`, `✓`, `×`.
- [ ] `ListRow.render_with_metadata/6` uses display-width math and keeps current ASCII layout behavior.
- [ ] Command-footer/chrome key hint output uses width-aware truncation or has an explicit width-safe contract covered by tests.
- [ ] Modal wrapping and reusable clipping/truncation paths use the shared helper for terminal display width.
- [ ] Composer cursor rendering is width-aware for visible terminal columns and does not split or visually misplace CJK, combining marks, or milestone glyph input.
- [ ] Character-count policies such as `max_post_length` are documented and tested as unchanged character limits.
- [ ] Representative width tests cover 64x22, 80x24, and at least one wide/tall terminal size.
- [ ] A focused source scan or equivalent test confirms migrated layout-sensitive paths no longer use direct `String.length/1`, `String.slice/2`, `String.slice/3`, or `String.pad_*` for terminal layout width.
- [ ] Existing ASCII-heavy widget and screen tests continue to pass.

## Ambiguity Report

| Dimension           | Score | Min   | Status | Notes |
|---------------------|-------|-------|--------|-------|
| Goal Clarity        | 0.92  | 0.75  | met    | Width-safe layout foundation is concrete and tied to Phase 16 WIDTH requirements. |
| Boundary Clarity    | 0.86  | 0.70  | met    | Facelift visuals, Chrome V2, theme/mode work, and product/domain changes are excluded. |
| Constraint Clarity  | 0.82  | 0.65  | met    | Raxol measurement, SSH-first boundary, terminal sizes, ASCII preservation, and character-count policy are locked. |
| Acceptance Criteria | 0.88  | 0.70  | met    | Pass/fail checks cover helper behavior, migrated paths, glyph classes, size contracts, and regression safety. |
| **Ambiguity**       | 0.12  | <=0.20 | met    | Gate passed. |

Status: met = dimension meets minimum, below = planner treats as assumption.

## Interview Log

Interactive question UI is unavailable in this Codex default-mode session, so the workflow fallback was used: conservative defaults were selected from the roadmap, requirements, `SCREENS.md`, and codebase scout.

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | What exists today for Unicode/display width? | Raxol exposes `Raxol.UI.TextMeasure`; Foglet lacks a local helper and has direct string operations in TUI layout-sensitive paths. |
| 2 | Researcher + Simplifier | What is the irreducible Phase 16 deliverable? | Add one shared Foglet TextWidth helper, migrate the highest-risk current paths, and prove the required glyph/size contracts without starting visual facelift work. |
| 3 | Boundary Keeper | What is explicitly not this phase? | Chrome V2, mode/theme contracts, rich rows, board/post/composer facelifts, browser UI, and domain changes are out of scope. |
| 4 | Failure Analyst | What would make the phase fail verification? | Unicode rows still misalign, composer cursor display splits/misplaces glyphs, migrated paths still use grapheme counts for terminal columns, or ASCII layouts regress. |
| 5 | Seed Closer | What remaining constraints must be locked before planning? | Character-count limits remain unchanged, tests must include 64x22/80x24/wide-tall contracts, and remaining direct string operations must be documented if they are not display-width-sensitive. |

---

*Phase: 16-unicode-width-foundation*
*Spec created: 2026-04-25*
*Next step: $gsd-discuss-phase 16 - implementation decisions (how to build what's specified above)*
