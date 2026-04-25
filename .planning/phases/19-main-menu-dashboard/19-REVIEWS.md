---
phase: 19
reviewers: [codex]
reviewed_at: 2026-04-25T19:35:10Z
plans_reviewed:
  - 19-01-PLAN.md
  - 19-02-PLAN.md
  - 19-03-PLAN.md
---

# Cross-AI Plan Review — Phase 19

## Codex Review

**Summary**

Phase 19 is generally well-scoped and the 01→02→03 dependency order is sensible: first separate destinations from command-bar actions, then change the body visual, then lock layout behavior with positioned-render tests. The plans stay within the SSH/TUI boundary, avoid new context queries, preserve direct hotkeys, and explicitly reject destination cursor/Enter navigation. The main risks are around whether the “structural” destinations/actions split is truly structural, whether fixed-width navigation rows satisfy right-alignment in real split-pane allocations, and whether the tests assert the right things without becoming brittle or missing command-bar/body distinctions.

**Per-Plan Analysis**

**19-01: Destinations vs. Actions Data Layer**

Scope is appropriate: refactor `lib/foglet_bbs/tui/screens/main_menu.ex` so destinations are body-only and actions are command-bar-only, then cover that in `test/foglet_bbs/tui/screens/main_menu_test.exs`.

Issues:

- The split is only partially structural. `visible_destinations/1` and `visible_actions/1` are separate public functions, but `visible_actions/1` does not derive from or validate against the destinations list. The non-overlap is enforced by tests and convention, not by one shared data model.
- Making private render helpers public just for tests is a mild API leak. It may be acceptable, but it should be intentional.
- The plan claims “single canonical destinations list that the body and command bar both derive from,” but command bar actions do not actually derive from destinations. They are independent.
- Test count mismatch: the plan says “8 tests” in `<done>` but describes 10 test cases.
- The anonymous destination contract includes `C Compose`, but if compose requires authentication in `handle_key/2`, the render and action behavior could diverge. The plan should explicitly verify anonymous `C` behavior if anonymous home is a supported state.

**19-02: Boxed Navigation + Oneliners Visual**

Scope is coherent: it consumes the Plan 01 lists and changes only the main-menu body.

Issues:

- `@nav_panel_inner_width 20` makes right-aligned keys align to a fixed budget, not to the actual split-pane panel width. At 80 or 132 columns, keys will not be right-aligned to the panel edge, which weakens D-08.
- The plan says glyph styling routes through theme slots, but the implementation renders glyph, label, and key as one `text/2` node using `theme.primary.fg`. That is theme-routed, but not glyph-specific slot routing.
- Tests use regexes against collected text, which validates content shape but not actual box borders or visual side-by-side layout. Plan 03 covers positioning later, so that is acceptable, but Plan 02’s “boxed” assertions are mostly source-grep based.
- `TextWidth.display_width(row) <= 20` is good for minimum width, but it does not prove the row is right-aligned within the actual navigation panel.
- The oneliner long-Unicode existing test reportedly uses `String.length(row) <= 39`; that is the wrong metric for Phase 16 width guarantees. It should use `TextWidth.display_width/1`.

**19-03: Size-Contract Assertions**

Scope is correct and belongs in `test/foglet_bbs/tui/layout_smoke_test.exs` per D-17.

Issues:

- The smoke test uses `role: :member` in the replacement test while the rest of the phase/spec uses `:user`. That is a real defect risk. `ShellVisibility.account_visible?/1` may tolerate any non-nil user, but moderation/sysop predicates and future role logic may not. Use `:user` consistently.
- “No two text elements share identical `{x, y}`” may be too strict depending on how Raxol positions nested text nodes, border/title text, or overlapping layout internals. Overlap should ideally compare ranges on the same `y`, not just identical starts.
- The test does not directly assert oneliner rows stay inside the right panel, only inside the viewport. That catches terminal overflow but not bleeding across the split boundary.
- The long-oneliner test name says “long-Unicode” but `String.duplicate("body ", 30)` is ASCII. It does not exercise CJK/combining width.
- `elements -- Enum.uniq_by(...)` is a weak duplicate diagnostic because struct/map equality and duplicate removal may not identify all colliding coordinate groups clearly.

**Strengths**

- Clear phase decomposition: data contract, visual refactor, positioned-render coverage.
- Good preservation of explicit out-of-scope decisions: no cursor, no Enter-to-open, no activity panel, no new data queries.
- Command-bar non-duplication is directly tested.
- Role visibility is covered for user/mod/sysop and negative H visibility for regular users.
- Uses existing repo primitives: `ShellVisibility`, `Bodyguard.permit?/4`, `ScreenFrame.render/4`, `split_pane`, `TextWidth`, and existing test files.
- The stale `Welcome` assertions in `test/foglet_bbs/tui/screens/main_menu_test.exs` and `test/foglet_bbs/tui/layout_smoke_test.exs` are explicitly called out and migrated.

**Concerns**

- **HIGH:** `19-03` uses `role: :member` in `test/foglet_bbs/tui/layout_smoke_test.exs` while the phase consistently uses `:user`. This can mask role-gating drift and should be fixed to `:user`.
- **MEDIUM:** The destinations/actions split in `lib/foglet_bbs/tui/screens/main_menu.ex` is not as structural as claimed. Independent public functions can drift unless there is a shared command model or explicit disjointness helper.
- **MEDIUM:** Fixed `@nav_panel_inner_width 20` proves minimum-size fit but not actual right alignment at wider sizes. It may satisfy “fits” but not “right-aligned key column.”
- **MEDIUM:** Plan 03’s overlap assertion checks identical `{x, y}` only. Text can overlap on the same line with different `x` ranges.
- **MEDIUM:** Long-Unicode acceptance is under-tested if assertions use `String.length/1` or ASCII-only repeated text.
- **LOW:** Public `visible_destinations/1` and `visible_actions/1` are test-friendly but expand the screen module API.
- **LOW:** Glyph color “through theme slots” is technically theme-routed, but the plan does not implement distinct glyph styling despite claiming it.

**Suggestions**

- In `lib/foglet_bbs/tui/screens/main_menu.ex`, make the split more structural by introducing one private canonical descriptor list with `kind: :destination | :action`, then derive `visible_destinations/1` and `visible_actions/1` from it. That would make non-overlap a property of data, not just tests.
- In `test/foglet_bbs/tui/layout_smoke_test.exs`, replace `role: :member` with `role: :user` in the Main Menu smoke state.
- In `test/foglet_bbs/tui/layout_smoke_test.exs`, replace identical-coordinate overlap checks with range checks: for each `y`, sort elements by `x` and assert `prev.x + TextWidth.display_width(prev.text) <= next.x`.
- In the 64x22 oneliner test, use CJK and combining-mark content, not only ASCII. Example bodies should include something like `"界界界"` and `"é"`, then assert via `TextWidth.display_width/1`.
- In `test/foglet_bbs/tui/screens/main_menu_test.exs`, avoid testing command-bar absence through raw `collect_text_values/1` where possible. Prefer inspecting `MainMenu.visible_actions/1` for command keys, because raw text can conflate body rows, command labels, and chrome text.
- Reconsider `@nav_panel_inner_width 20`. Either rename it as a minimum-width row budget, or compute the row budget from `state.terminal_size` using the same conservative split-pane assumptions. Current behavior will look under-aligned at wide sizes.
- If glyph-specific theming matters for D-08, use a row/inline composition that lets glyphs use `theme.success.fg`, `theme.info.fg`, etc. If single-color rows are acceptable, update the plan language to say “theme-routed row styling,” not “glyph color routes through slots.”

**Risk Assessment**

Overall risk: **MEDIUM**.

The implementation scope is small and the plan avoids the biggest architectural hazards: no new queries, no shared Chrome rewrites, no destination cursor, no browser UI. The risk is mainly test/design precision. The role atom inconsistency is a concrete defect, and the fixed-width navigation budget may pass tests while failing the intended “right-aligned within panel” visual. Tightening the structural split and improving the positioned-render assertions would move this closer to low risk.

---

## Consensus Summary

Only one reviewer (Codex) participated in this round, so the "consensus" below reflects Codex's assessment alone. To get cross-AI agreement, re-run with `/gsd-review --phase 19 --gemini --claude` (or `--all`).

### Agreed Strengths

- Clear three-wave decomposition (data → visual → size contract) with appropriate dependency ordering.
- Phase boundaries faithfully preserve SPEC out-of-scope decisions: no destination cursor, no new data queries, no activity panel, no Chrome rewrites.
- Heavy reuse of existing primitives (`ShellVisibility`, `TextWidth`, `Bodyguard`, `ScreenFrame`, `split_pane`) keeps churn small.
- The stale `"Welcome"` assertions in both `main_menu_test.exs` and `layout_smoke_test.exs` are explicitly migrated, not left to drift.

### Agreed Concerns

1. **HIGH — Role atom inconsistency.** `19-03-PLAN.md` Step 1 uses `role: :member` for the smoke-test user while the rest of Phase 19 (SPEC, CONTEXT, plans 01/02) uses `:user`. Could mask role-gating drift in future predicate changes. Fix to `:user`.
2. **MEDIUM — Destinations/actions split is not structurally enforced.** D-01 promises a single source of truth, but `visible_destinations/1` and `visible_actions/1` are independent public functions whose non-overlap is enforced only by Test 9 (the B/C/A/M/S/Q forbidden-key sweep). A shared private descriptor list with a `:kind` tag would make non-overlap a data property.
3. **MEDIUM — `@nav_panel_inner_width 20` proves "fits" but not "right-aligned."** At 80 or 132 columns the right-aligned key column will float in mid-panel rather than hugging the panel edge, which weakens the D-08 visual contract. Either compute the budget from `state.terminal_size` or rename the constant to clarify it is a minimum.
4. **MEDIUM — Plan 03 overlap assertion is too narrow.** Identical `{x, y}` collision is rarer than range overlap on the same `y`; replace with a per-`y` sort + `prev.x + display_width(prev.text) <= next.x` check.
5. **MEDIUM — Long-Unicode test does not actually exercise Unicode.** `String.duplicate("body ", 30)` in 19-03 Step 3 is ASCII; CJK and combining-mark content is needed to exercise the Phase 16 width guarantees the test is named after.
6. **LOW — Public `visible_destinations/1` / `visible_actions/1` expand the screen API for test convenience.** Acceptable, but should be intentional.
7. **LOW — Glyph theme-slot claim is overstated.** The implementation renders glyph + label + key as one `text/2` node with `theme.primary.fg`; claims of glyph-specific slot routing in 19-02 D-08 should either be implemented per-glyph or softened in the plan language.

### Divergent Views

N/A — only one reviewer in this round.
