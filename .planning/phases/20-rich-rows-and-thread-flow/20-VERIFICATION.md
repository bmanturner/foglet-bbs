---
phase: 20-rich-rows-and-thread-flow
verified: 2026-04-25T21:16:55Z
status: gaps_found
score: 3/4 must-haves verified
overrides_applied: 0
gaps:
  - truth: "The row primitive is reusable by later board/operator surfaces."
    status: failed
    reason: "RichRow accepts arbitrary state atoms but only renders glyphs for :unread, :sticky, and :locked. Non-ThreadList state atoms are silently rendered as blank slots, so later callers cannot express their own visible state glyphs without editing RichRow."
    artifacts:
      - path: "lib/foglet_bbs/tui/widgets/list/rich_row.ex"
        issue: "glyph_nodes/3 hardcodes the three ThreadList states and discards all other atoms."
      - path: "test/foglet_bbs/tui/widgets/list/rich_row_test.exs"
        issue: "The generic-state test only asserts unknown atoms do not leak labels and keep width; it does not assert a renderable non-ThreadList glyph contract."
    missing:
      - "Add a documented generic renderable state-cell API, or an extensible mapping input, so future callers can supply visible glyphs and theme slots without changing RichRow."
      - "Update the generic-state test to assert expected non-ThreadList glyph output and styling, not only blank width preservation."
---

# Phase 20: Rich Rows and Thread Flow Verification Report

**Phase Goal:** Thread browsing uses semantic, width-safe rows that make unread, sticky, locked, author, count, and age easy to scan.
**Verified:** 2026-04-25T21:16:55Z
**Status:** gaps_found
**Re-verification:** No - initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | Users can distinguish unread/read and sticky/locked state without relying only on text labels. | VERIFIED | `ThreadList.render_thread_row/4` builds `[:unread, :sticky, :locked]` state clusters from thread data and calls `RichRow.render/1`; tests assert `◆`, `●`, and `⚿` appear and `[S] ` is absent. |
| 2 | Thread metadata aligns correctly with Unicode state glyphs and variable-width titles. | VERIFIED | `RichRow.compute_parts/4` reserves marker + 4-cell cluster width before title/metadata layout; 64/80/132 layout smoke tests assert glyphs, metadata, truncation, and width budget. |
| 3 | Focused-thread details appear without disrupting keyboard navigation. | VERIFIED | Phase 20 explicitly accepts THREADS-02 as selection clarity rather than a details strip in `20-VALIDATION.md`; focused rows use `▌ ` and `theme.selected.bg`, while `handle_key/2` navigation/open/compose/back remains intact. |
| 4 | The row primitive is reusable by later board/operator surfaces. | FAILED | `RichRow` documents generic `state_cluster` atoms, but `glyph_nodes/3` renders only `:unread`, `:sticky`, and `:locked`; `[:subscribed, :required]` produces blank slots and cannot express future visible state glyphs. |

**Score:** 3/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `lib/foglet_bbs/tui/widgets/list/rich_row.ex` | Stateless RichRow widget with documented render API | PARTIAL | Exists and is substantive; wired to ThreadList. Fails reusable state-glyph API for non-ThreadList states. |
| `lib/foglet_bbs/tui/screens/thread_list.ex` | Thread list rows rendered through RichRow with no `[S] ` prefix | VERIFIED | `RichRow.render/1` called at `render_thread_row/4`; title is read directly from `thread.title`; `ListRow.render_with_metadata/6` is absent from ThreadList. |
| `test/foglet_bbs/tui/widgets/list/rich_row_test.exs` | RichRow unit coverage | PARTIAL | Covers glyphs, metadata, selection, width, theme hygiene; generic-state assertion is too weak and permits blank future states. |
| `test/foglet_bbs/tui/screens/thread_list_test.exs` | ThreadList glyph and metadata coverage | VERIFIED | Includes FakeLockedThreads, glyph assertions, `[S] ` absence, metadata preservation, and leading-cluster width checks. |
| `test/foglet_bbs/tui/layout_smoke_test.exs` | 64x22, 80x24, 132x50 size contract | VERIFIED | `thread_list - size contract` block asserts row-isolated glyphs, metadata, truncation, and width budget. |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `ThreadList.render_thread_row/4` | `RichRow.render/1` | Alias + render call | WIRED | Source calls `RichRow.render(title:, metadata:, state_cluster:, selected:, theme:, width:, emphasis:)`. |
| `ThreadList.render_thread_row/4` | Thread state fields | `Map.get/3` | WIRED | Uses `Map.get(thread, :has_unread, false)`, `:sticky`, and `:locked` to build state_cluster. |
| `RichRow.render/1` | `Foglet.TUI.TextWidth` | Display-width helpers | WIRED | Uses `TextWidth.display_width/1`, `TextWidth.truncate/2`, and `TextWidth.pad_trailing/2`. |
| `RichRow.render/1` | `Foglet.TUI.Theme` | Theme slot lookups | WIRED | Uses theme accent/info/warning/dim/selected/unselected slots; no hardcoded color atoms found in RichRow. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|---|---|---|---|---|
| `ThreadList` | `current_thread_list` | Existing state or `load_threads/2` domain adapter | Yes | FLOWING - render consumes loaded thread entries; tests inject fakes and verify rendered output. |
| `RichRow` | `state_cluster`, `title`, `metadata` | Caller-supplied keyword API | Partial | HOLLOW for future state glyphs - ThreadList data flows, but generic state atoms do not produce visible glyph data. |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Focused Phase 20 widget/screen/layout tests pass | `rtk mix test test/foglet_bbs/tui/widgets/list/rich_row_test.exs test/foglet_bbs/tui/screens/thread_list_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` | `75 tests, 0 failures` | PASS |
| Project precommit gate | `rtk mix precommit` | Fails with two Credo refactoring findings in `lib/foglet_bbs/tui/screens/main_menu.ex:223` and `:245` | WARNING - unrelated pre-existing blocker outside Phase 20 files |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| RICHROW-01 | 20-01, 20-03, 20-04, 20-06 | Reusable rich-row primitive supports state glyphs, primary text, metadata, optional subtitle/details, selection, theme routing. | BLOCKED | ThreadList-specific states work, but reusable non-ThreadList state glyphs are blank. Subtitle/details were explicitly out of Phase 20 scope in `20-SPEC.md`; the reusable state-glyph API remains the blocking gap. |
| THREADS-01 | 20-02, 20-03, 20-05, 20-06 | Thread list rows expose unread/read, sticky, locked, author, reply count, and age in width-safe aligned rows. | SATISFIED | Glyph and metadata tests pass; layout smoke covers 64x22, 80x24, 132x50. |
| THREADS-02 | 20-01, 20-04, 20-05, 20-06 | Focused-thread details without disrupting keyboard navigation/open/compose/back. | SATISFIED BY ACCEPTED INTERPRETATION | `20-VALIDATION.md` records selection clarity as the accepted product decision; tests assert focused-row uniqueness and existing navigation tests pass. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---:|---|---|---|
| `test/foglet_bbs/tui/layout_smoke_test.exs` | 106, 970, 1086, 1319 | `placeholder:` test fixture input | INFO | Benign test data, not a stub. |
| `lib/foglet_bbs/tui/widgets/list/rich_row.ex` | 96-103 | Generic state atoms discarded into blank fixed slots | BLOCKER | Prevents the reusable state-glyph API from satisfying the phase contract. |

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

Most ThreadList-facing behavior is implemented and covered: `[S] ` is removed, state glyphs render, metadata is preserved, selection remains clear, and the 64x22 size contract is tested. The blocking gap is narrower: `RichRow` is not actually reusable for future visible state glyphs. Its public input accepts generic atoms, but implementation only knows the three ThreadList atoms and renders all others as blanks.

The precommit failure is not a Phase 20 product-code gap: current `rtk mix precommit` stops on two Credo refactoring findings in `main_menu.ex`, matching the unrelated blocker documented in `20-VALIDATION.md`.

---

_Verified: 2026-04-25T21:16:55Z_
_Verifier: the agent (gsd-verifier)_
