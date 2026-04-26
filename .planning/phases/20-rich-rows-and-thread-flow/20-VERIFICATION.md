---
phase: 20-rich-rows-and-thread-flow
verified: 2026-04-26T08:58:00-05:00
status: verified
score: 4/4 must-haves verified
overrides_applied: 0
gaps: []
---

# Phase 20: Rich Rows and Thread Flow Verification Report

**Phase Goal:** Thread browsing uses semantic, width-safe rows that make unread, sticky, locked, author, count, and age easy to scan.
**Verified:** 2026-04-26T08:58:00-05:00
**Status:** verified
**Re-verification:** Yes - RICHROW-01 generic state-cell gap rechecked

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | Users can distinguish unread/read and sticky/locked state without relying only on text labels. | VERIFIED | `ThreadList.render_thread_row/4` builds `[:unread, :sticky, :locked]` state clusters from thread data and calls `RichRow.render/1`; tests assert `◆`, `●`, and `⚿` appear and `[S] ` is absent. |
| 2 | Thread metadata aligns correctly with Unicode state glyphs and variable-width titles. | VERIFIED | `RichRow.compute_parts/4` reserves marker + 4-cell cluster width before title/metadata layout; 64/80/132 layout smoke tests assert glyphs, metadata, truncation, and width budget. |
| 3 | Focused-thread details appear without disrupting keyboard navigation. | VERIFIED | Phase 20 explicitly accepts THREADS-02 as selection clarity rather than a details strip in `20-VALIDATION.md`; focused rows use `▌ ` and `theme.selected.bg`, while `handle_key/2` navigation/open/compose/back remains intact. |
| 4 | The row primitive is reusable by later board/operator surfaces. | VERIFIED | `RichRow` documents explicit caller-owned state cells such as `%{key: :subscribed, glyph: "◆", slot: :success}`. `state_cells/1` accepts those cells, `glyph_node/3` renders their visible glyphs through caller-selected theme slots, and tests assert `:subscribed` / `:required` cells render visible glyphs without domain coupling. |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `lib/foglet_bbs/tui/widgets/list/rich_row.ex` | Stateless RichRow widget with documented render API | VERIFIED | Exists and is substantive; wired to ThreadList. The public docs describe explicit state cells with caller-owned glyphs and theme slots for future board/operator surfaces. |
| `lib/foglet_bbs/tui/screens/thread_list.ex` | Thread list rows rendered through RichRow with no `[S] ` prefix | VERIFIED | `RichRow.render/1` called at `render_thread_row/4`; title is read directly from `thread.title`; `ListRow.render_with_metadata/6` is absent from ThreadList. |
| `test/foglet_bbs/tui/widgets/list/rich_row_test.exs` | RichRow unit coverage | VERIFIED | Covers glyphs, metadata, selection, width, theme hygiene, explicit generic state cells, visible non-ThreadList glyph output, and selected generic-cell styling. |
| `test/foglet_bbs/tui/screens/thread_list_test.exs` | ThreadList glyph and metadata coverage | VERIFIED | Includes FakeLockedThreads, glyph assertions, `[S] ` absence, metadata preservation, and leading-cluster width checks. |
| `test/foglet_bbs/tui/layout_smoke_test.exs` | 64x22, 80x24, 132x50 size contract | VERIFIED | `thread_list - size contract` block asserts row-isolated glyphs, metadata, truncation, and width budget. |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `ThreadList.render_thread_row/4` | `RichRow.render/1` | Alias + render call | WIRED | Source calls `RichRow.render(title:, metadata:, state_cluster:, selected:, theme:, width:, emphasis:)`. |
| `ThreadList.render_thread_row/4` | Thread state fields | `Map.get/3` | WIRED | Uses `Map.get(thread, :has_unread, false)`, `:sticky`, and `:locked` to build state_cluster. |
| `RichRow.render/1` | `Foglet.TUI.TextWidth` | Display-width helpers | WIRED | Uses `TextWidth.display_width/1`, `TextWidth.truncate/2`, and `TextWidth.pad_trailing/2`. |
| `RichRow.render/1` | `Foglet.TUI.Theme` | Theme slot lookups | WIRED | Uses theme accent/info/warning/dim/selected/unselected slots; no hardcoded color atoms found in RichRow. |
| `RichRow.render/1` | Caller-owned state cells | `%{glyph: String.t(), slot: atom()}` entries in `state_cluster` | WIRED | Explicit cells render visible glyphs in caller order up to the fixed cluster slot count and route foreground through the supplied theme slot. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|---|---|---|---|---|
| `ThreadList` | `current_thread_list` | Existing state or `load_threads/2` domain adapter | Yes | FLOWING - render consumes loaded thread entries; tests inject fakes and verify rendered output. |
| `RichRow` | `state_cluster`, `title`, `metadata` | Caller-supplied keyword API | Yes | FLOWING - ThreadList atoms render built-in glyphs, and caller-owned explicit state cells render visible non-ThreadList glyphs without editing RichRow. |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| RichRow generic state-cell tests pass | `rtk mix test test/foglet_bbs/tui/widgets/list/rich_row_test.exs` | `26 tests, 0 failures` | PASS |
| Focused Phase 20 widget/screen/layout tests pass | `rtk mix test test/foglet_bbs/tui/widgets/list/rich_row_test.exs test/foglet_bbs/tui/screens/thread_list_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` | `107 tests, 0 failures` | PASS |
| Project precommit gate | `rtk mix precommit` | Fails with two Credo refactoring findings in `lib/foglet_bbs/tui/screens/main_menu.ex:223` and `:245` | WARNING - unrelated pre-existing blocker outside Phase 20 files |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| RICHROW-01 | 20-01, 20-03, 20-04, 20-06 | Reusable rich-row primitive supports state glyphs, primary text, metadata, optional subtitle/details, selection, theme routing. | SATISFIED | ThreadList-specific states work, and explicit generic state cells give future callers a documented visible glyph + theme-slot API. Subtitle/details were explicitly out of Phase 20 scope in `20-SPEC.md`. |
| THREADS-01 | 20-02, 20-03, 20-05, 20-06 | Thread list rows expose unread/read, sticky, locked, author, reply count, and age in width-safe aligned rows. | SATISFIED | Glyph and metadata tests pass; layout smoke covers 64x22, 80x24, 132x50. |
| THREADS-02 | 20-01, 20-04, 20-05, 20-06 | Focused-thread details without disrupting keyboard navigation/open/compose/back. | SATISFIED BY ACCEPTED INTERPRETATION | `20-VALIDATION.md` records selection clarity as the accepted product decision; tests assert focused-row uniqueness and existing navigation tests pass. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---:|---|---|---|
| `test/foglet_bbs/tui/layout_smoke_test.exs` | 106, 970, 1086, 1319 | `placeholder:` test fixture input | INFO | Benign test data, not a stub. |
| `lib/foglet_bbs/tui/widgets/list/rich_row.ex` | N/A | Generic state atoms discarded into blank fixed slots | RESOLVED | Explicit state cells now render visible caller-owned glyphs and route styling through caller-selected theme slots. Unknown bare atoms still render as no-op input, which preserves compatibility. |

### Human Verification Required

#### 1. Terminal Glyph Contrast Across Themes

**Test:** SSH into the TUI, switch through available themes, and view rows covering unread, sticky, locked, selected, and unselected states.
**Expected:** `◆`, `●`, and `⚿` remain visually distinct from row background and from each other.
**Why human:** Real terminal font/color contrast cannot be fully verified from render trees.

#### 2. Locked Glyph Font Coverage

**Test:** View a locked thread row from PuTTY and Windows Terminal.
**Expected:** `⚿` renders as a visible single-cell glyph, not tofu.
**Why human:** Cross-terminal glyph availability depends on client font/environment.

#### 3. Selected State-Glyph Precedence

**Test:** Focus sticky, unread, and locked rows in the SSH TUI.
**Expected:** The selected row background is clear and each state glyph still reads as its semantic color.
**Why human:** Code verifies style data, but perceived contrast needs real terminal review.

### Gaps Summary

No Phase 20 product gaps remain after re-verifying RICHROW-01. `RichRow` now has a documented explicit state-cell API for visible non-ThreadList glyphs, and tests assert both unselected and selected generic-cell rendering. ThreadList-facing behavior remains covered: `[S] ` is removed, state glyphs render, metadata is preserved, selection remains clear, and the 64/80/132 size contract is tested.

The precommit failure is not a Phase 20 product-code gap: current `rtk mix precommit` stops on two Credo refactoring findings in `main_menu.ex`, matching the unrelated blocker documented in `20-VALIDATION.md`.

---

_Verified: 2026-04-26T08:58:00-05:00_
_Verifier: the agent (gsd-verifier)_
