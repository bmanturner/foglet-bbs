---
phase: 26
slug: layout-width-foundations
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-26
---

# Phase 26 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit |
| **Config file** | `mix.exs` |
| **Quick run command** | `rtk mix test test/foglet_bbs/tui/text_width_test.exs test/foglet_bbs/tui/widgets/display/table_test.exs test/foglet_bbs/tui/widgets/display/console_table_test.exs` |
| **Full suite command** | `rtk mix precommit` |
| **Estimated runtime** | ~120 seconds focused, precommit varies |

## Sampling Rate

- **After every task commit:** Run the task's focused `rtk mix test ...` command.
- **After every plan wave:** Run `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs`.
- **Before `$gsd-verify-work`:** `rtk mix precommit` must be green.
- **Max feedback latency:** 180 seconds for focused tests.

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 26-01-01 | 01 | 1 | LAYOUT-06 | — | N/A | unit | `rtk mix test test/foglet_bbs/tui/text_width_test.exs` | yes | pending |
| 26-01-02 | 01 | 1 | LAYOUT-04, LAYOUT-05 | — | N/A | unit/render | `rtk mix test test/foglet_bbs/tui/widgets/display/table_test.exs test/foglet_bbs/tui/widgets/display/console_table_test.exs` | yes | pending |
| 26-02-01 | 02 | 2 | LAYOUT-01 | — | N/A | render/smoke | `rtk mix test test/foglet_bbs/tui/widgets/input/tabs_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` | yes | pending |
| 26-02-02 | 02 | 2 | LAYOUT-02, LAYOUT-05 | — | N/A | screen/render | `rtk mix test test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` | yes | pending |
| 26-03-01 | 03 | 2 | LAYOUT-03 | — | N/A | screen/render | `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/widgets/list/board_tree_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` | yes | pending |
| 26-04-01 | 04 | 3 | POST-01 | — | N/A | unit/render | `rtk mix test test/foglet_bbs/tui/widgets/post/markdown_body_test.exs test/foglet_bbs/tui/screens/post_reader_test.exs` | yes | pending |
| 26-04-02 | 04 | 3 | LAYOUT-01..06, POST-01 | — | N/A | full/manual | `rtk mix precommit` | yes | pending |

## Wave 0 Requirements

Existing test infrastructure covers all phase requirements.

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Account, Moderation, Sysop tabs at 64x22 | LAYOUT-01 | Border-glyph artifacts are terminal-renderer sensitive | SSH into local app at 64x22; visit Account, Moderation, Sysop; confirm rightmost tab-row column aligns with frame `│` and no extra tab glyphs render past the rightmost tab |
| Moderation LOG/USERS/BOARDS at 64x22 | LAYOUT-02 | Final fit depends on real terminal and command-bar frame | SSH at 64x22; enter each tab with representative rows; confirm active tab and primary table remain in-frame and navigable |
| Boards overlarge directory at 64x22 | LAYOUT-03 | Requires representative overlarge directory and real keyboard navigation | Seed/create enough categories/boards to exceed visible rows; SSH at 64x22; confirm selection stays in-frame while navigating |
| Sysop INVITES at 80x24 | LAYOUT-04 | Visual separation is best verified in a terminal | SSH as sysop at 80x24 with available/consumed/revoked invites; confirm Code, Status, Created, Used by are visibly separated |
| Moderation LOG timezone and ellipsis at 80x24 | LAYOUT-05 | User timezone display and ellipsis must be read in terminal | Set user timezone to a non-UTC IANA zone; create long moderation log reason/body; confirm timestamp reflects preference and long text elides with `…` |
| Post reader paragraph breaks | POST-01 | PostReader viewport rendering is an end-to-end terminal path | Open a post with soft breaks, two blank-line paragraph breaks, and three-or-more newline runs; confirm soft breaks are line breaks and blank runs show exactly one blank visible line |

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies.
- [x] Sampling continuity: no 3 consecutive tasks without automated verify.
- [x] Wave 0 covers all MISSING references.
- [x] No watch-mode flags.
- [x] Feedback latency < 180s for focused tests.
- [x] `nyquist_compliant: true` set in frontmatter.

**Approval:** pending

