---
phase: 32-main-menu-chrome-polish
verified: 2026-04-27T22:18:00Z
status: passed
score: 5/5 must-haves verified
overrides_applied: 0
---

# Phase 32: Main Menu Chrome Polish — Verification Report

**Phase Goal:** Main Menu Navigation and Oneliners panels render their titles
embedded in the box top border, route every color through `Foglet.TUI.Theme`,
accent the bracketed key glyph, fix indent alignment, and remove the Oneliners
top-border glyph artifact.

**Verified:** 2026-04-27T22:18:00Z
**Status:** passed
**Re-verification:** No — initial verification.

## Must-Haves (merged from ROADMAP success criteria + SPEC requirements)

ROADMAP success criteria 1–5 map 1:1 to SPEC requirements MENU-01..MENU-05.
The merged list is the SPEC requirements (which are more specific and contain
the same coverage as the roadmap SCs).

## Goal Achievement

### Observable Truths

| #   | Truth (Requirement)                                                                                                                                  | Status     | Evidence                                                                                                          |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- | ----------------------------------------------------------------------------------------------------------------- |
| 1   | **MENU-01** Both inner panels render titles embedded in top border (`┌─ Navigation ─┐`-style); no body-row title.                                    | ✓ VERIFIED | Render at 80×24 shows `│┌─ Navigation ───────────────┐ ┌─ Oneliners ─────────────────────────────────┐│`. Layout-smoke test asserts `" Navigation "` / `" Oneliners "` overlays present and refutes bare body-row titles (`layout_smoke_test.exs:1100-1111`). |
| 2   | **MENU-02** Oneliners top border is clean at widths 64, 65, 66, 80, 81 — only `{┌, ─, ┐, space}` plus title segment, no `\|` artifact.               | ✓ VERIFIED | Pipe count on Oneliners-title row at all 5 canonical widths = 0. Top borders verified clean: e.g. width 64 → `┌─ Oneliners ───────────────────────┐`. Fix lives in `vendor/raxol/lib/raxol/ui/layout/split_pane.ex` (per-row `:text` elements) + `divider_char: " "` in `main_menu.ex:102`. |
| 3   | **MENU-03** Each nav row's key renders as bracketed `[X]` token in `theme.accent.fg`, distinct from label in `theme.primary.fg`.                     | ✓ VERIFIED | `nav_row/3` (`main_menu.ex:338-360`) emits `row [], do: [text(prefix, fg: theme.primary.fg), text("[" <> key <> "]", fg: theme.accent.fg)]` — two distinct text nodes. Render at 80×24 shows `[B] [C] [A] [M] [S] [Q]` on each visible row. Test asserts `"[B]" in texts` / `"[Q]" in texts` (`main_menu_test.exs:270,282`). |
| 4   | **MENU-04** Nav rows indented one column inside the panel's left border (first character after `│` is U+0020).                                       | ✓ VERIFIED | `nav_row/3` prepends `indent = " "` (`main_menu.ex:339,342`). Render shows `││ ● Boards…[B]│` at 64/80/132 — exactly one space after the inner panel `│`. |
| 5   | **MENU-05** Zero hardcoded color literals in `main_menu.ex`; all colors flow through `theme.<slot>.fg`.                                              | ✓ VERIFIED | `grep -nE 'IO\.ANSI\|\\e\[\|fg:\s*:[a-z]+\|fg:\s*"#[0-9a-fA-F]'` against `lib/foglet_bbs/tui/screens/main_menu.ex` returns zero matches. |

**Score:** 5/5 truths verified.

### Required Artifacts

| Artifact                                                              | Expected                                                                                                                                                       | Status     | Details                                                                                                                                                                                                                       |
| --------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/foglet_bbs/tui/screens/main_menu.ex`                             | `nav_panel/3` and `oneliners_panel/2` emit `%{type: :panel, attrs: %{title:, title_attrs:, border:, border_fg:, width: 9999, height: 9999}, children: [...]}` | ✓ VERIFIED | Read at lines 310-327 (nav_panel) and 362-379 (oneliners_panel) — exact shape, theme-routed.                                                                                                                                  |
| `lib/foglet_bbs/tui/screens/main_menu.ex` `nav_row/3`                 | Multi-node row composition: primary label text + accent `[X]` text                                                                                             | ✓ VERIFIED | Lines 338-360. `row [], do: [...]` macro form (with documented note about `row/1` function vs `row/2` macro pitfall). Two `text/2` nodes with distinct `fg` slots.                                                              |
| `lib/foglet_bbs/tui/screens/main_menu.ex` `render/1` `split_pane`     | `divider_char: " "` passed to suppress horizontal-divider over-paint                                                                                           | ✓ VERIFIED | Line 102 — `divider_char: " "` with explanatory comment lines 88-96 referencing the vendor fix.                                                                                                                                |
| `vendor/raxol/lib/raxol/ui/layout/split_pane.ex`                      | `build_divider(:horizontal, ...)` emits per-row `:text` elements; new `:divider_char` attr supported                                                            | ✓ VERIFIED | Pipe-count test at all 5 canonical widths = 0 — only possible if divider is now correctly oriented and accepts the space override. Commit `739122f` documents the patch.                                                       |
| `test/foglet_bbs/tui/layout_smoke_test.exs`                           | Assertions migrated to embedded-title shape + multi-node nav rows                                                                                              | ✓ VERIFIED | Lines 1100-1111, 1118-1128 — exact assertions on `" Navigation "`, `" Oneliners "`, `"[B]"`, `"[Q]"`. Right-panel containment anchored on `oneliners_header.x - 1` (lines 1271, 1336).                                       |
| `test/foglet_bbs/tui/screens/main_menu_test.exs`                      | Refute body-row titles; assert `[B]`/`[Q]` text nodes; leading-segment regex                                                                                   | ✓ VERIFIED | Lines 92, 101, 260 (refutes); 270, 282 (`"[B]" in texts`, `"[Q]" in texts`).                                                                                                                                                  |

### Key Link Verification

| From                                  | To                                                                  | Via                                                                                              | Status   | Details                                                                                                                                                  |
| ------------------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ | -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `MainMenu.render/1`                   | Raxol `:panel` element                                              | `nav_panel/3`, `oneliners_panel/2` returning maps with `type: :panel`                            | ✓ WIRED  | Both helpers called in `render/1` (lines 85-86); maps consumed by Raxol's `Panels.process` to overlay title onto top border row.                          |
| `nav_row/3` accent token              | `theme.accent.fg`                                                   | second `text/2` node                                                                             | ✓ WIRED  | Line 357 — `text(bracketed_key, fg: theme.accent.fg)`.                                                                                                  |
| `MainMenu.render/1` split_pane        | `vendor/raxol/.../split_pane.ex` patched divider                     | `divider_char: " "` keyword                                                                      | ✓ WIRED  | Line 102 → consumed by `SplitPane.process` → `build_divider(:horizontal, ...)`. End-to-end verified by clean Oneliners borders at all 5 widths.            |
| Test suite                            | Render shape contract                                                | `text_elements(positioned)` and `collect_text_values/1`                                          | ✓ WIRED  | 130 tests pass across both files; assertions exercise the new shape (border-embedded title + multi-node row + indent).                                  |

### Data-Flow Trace (Level 4)

The Main Menu's "data" is the static `@main_menu_commands` descriptor list
(line 63) plus `state.recent_oneliners`. Both render paths traced:

| Artifact                       | Data Variable               | Source                                       | Produces Real Data | Status      |
| ------------------------------ | --------------------------- | -------------------------------------------- | ------------------ | ----------- |
| `nav_panel/3`                  | `destinations`              | `visible_destination_entries(user)` filters `@main_menu_commands` | Yes (compile-time list)  | ✓ FLOWING |
| `oneliners_panel/2`            | `entries`                   | `state.recent_oneliners` (or empty fallback) | Yes (real state or empty-message)| ✓ FLOWING |
| `nav_row/3` accent text        | `bracketed_key = "[K]"`     | descriptor's `:key` (B/C/A/M/S/Q)            | Yes                | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior                                                              | Command                                                                                              | Result                                          | Status   |
| --------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ----------------------------------------------- | -------- |
| Render contains `─ Navigation ─` substring at 80×24                   | `mix foglet.tui.render main_menu --width 80 --height 24`                                             | Substring present on row 1 of inner content     | ✓ PASS   |
| Render contains `─ Oneliners ─` substring at 80×24                    | (same)                                                                                               | Substring present on same row                   | ✓ PASS   |
| Pipe count on Oneliners-title row at width 64                          | `… --width 64 --height 22 \| grep '─ Oneliners' \| grep -o '\|' \| wc -l`                          | 0                                               | ✓ PASS   |
| Pipe count at width 65                                                 | (same, --width 65)                                                                                   | 0                                               | ✓ PASS   |
| Pipe count at width 66                                                 | (same, --width 66)                                                                                   | 0                                               | ✓ PASS   |
| Pipe count at width 80                                                 | (same, --width 80)                                                                                   | 0                                               | ✓ PASS   |
| Pipe count at width 81                                                 | (same, --width 81)                                                                                   | 0                                               | ✓ PASS   |
| `[B]`, `[C]`, `[A]`, `[M]`, `[S]`, `[Q]` all appear at right edge      | grep across the 80×24 render                                                                         | All 6 bracketed tokens present, right-aligned    | ✓ PASS   |
| Indent: first char after `│` on every nav row is U+0020                | grep `││ ● Boards`, `││ ✎ Compose`, etc                                                            | All 6 visible rows indented                     | ✓ PASS   |
| MENU-05 grep returns 0 matches                                        | `grep -nE 'IO\.ANSI\|\\e\[\|fg:\s*:[a-z]+\|fg:\s*"#[0-9a-fA-F]' lib/.../main_menu.ex`               | 0 matches                                       | ✓ PASS   |
| Test suite (layout_smoke + main_menu_test)                            | `mix test test/foglet_bbs/tui/layout_smoke_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs` | 130 tests, 0 failures                            | ✓ PASS   |

### Requirements Coverage

| Requirement | Source Plan(s)              | Description                                                                | Status      | Evidence                                                |
| ----------- | --------------------------- | -------------------------------------------------------------------------- | ----------- | ------------------------------------------------------- |
| MENU-01     | 32-01, 32-03                | Border-embedded panel titles                                                | ✓ SATISFIED | Render output + layout_smoke assertions                  |
| MENU-02     | 32-02                        | Oneliners top-border artifact removed at 64/65/66/80/81                     | ✓ SATISFIED | Pipe-count = 0 at all 5 widths                          |
| MENU-03     | 32-01, 32-03                | Bracketed accent key in `theme.accent.fg`                                   | ✓ SATISFIED | `nav_row/3` two-node composition + test assertions     |
| MENU-04     | 32-01, 32-03                | One-column inner indent                                                     | ✓ SATISFIED | Indent prepended in `nav_row/3`; observed in renders   |
| MENU-05     | 32-01, 32-02, 32-03         | Zero hardcoded color literals; theme-only routing                           | ✓ SATISFIED | grep gate returns 0 matches                             |

No orphaned requirements: SPEC enumerates exactly MENU-01..MENU-05 and all are
covered.

### Anti-Patterns Found

| File                                              | Line  | Pattern                                                                                | Severity | Impact                                                                                                                                                                |
| ------------------------------------------------- | ----- | -------------------------------------------------------------------------------------- | -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/foglet_bbs/tui/screens/main_menu.ex`         | 56-62 | D-08 deferral comment text says "row text is rendered as a single text node"           | ℹ️ Info  | Comment is now technically stale — `nav_row/3` is multi-node post-Phase 32 — but the *deferral statement* (per-glyph slot routing for `●`/`⚑`/etc. is not done) remains accurate. SPEC explicitly required this comment to remain. Not a goal-blocker; the deferral itself still holds. Could be tightened in a future cleanup. |

No blocker or warning anti-patterns found.

### Human Verification Required

None. All acceptance criteria are observable via `mix foglet.tui.render` output
and the grep gate; the SPEC explicitly opted for "fix it, don't test it" (no
new tests required), and the test-update plan covered the existing assertion
suite. ROADMAP SC-5 mentions "verified by snapshot test against both themes" —
the SPEC narrowed this to the grep-based color-literal check, which passes.
Live SSH visual inspection at 64×22 / 80×24 / 132×50 is optional but not
required by the SPEC's acceptance criteria.

### Gaps Summary

No gaps. All 5 requirements (MENU-01..MENU-05) verified. Render contracts hold
at all 5 canonical widths (64/65/66/80/81). Test suite is green. Theme routing
gate is clean. Vendor change to `split_pane.ex` is documented, minimal, and
backward-compatible (default `:divider_char` preserves prior behavior for any
future consumer).

---

_Verified: 2026-04-27T22:18:00Z_
_Verifier: Claude (gsd-verifier)_
