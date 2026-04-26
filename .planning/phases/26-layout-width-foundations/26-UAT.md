---
status: partial
phase: 26-layout-width-foundations
source:
  - .planning/phases/26-layout-width-foundations/26-01-SUMMARY.md
  - .planning/phases/26-layout-width-foundations/26-02-SUMMARY.md
  - .planning/phases/26-layout-width-foundations/26-03-SUMMARY.md
  - .planning/phases/26-layout-width-foundations/26-04-SUMMARY.md
started: 2026-04-26T22:32:00Z
updated: 2026-04-26T23:38:43Z
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

[gap-closure patch landed; manual SSH rerun still pending for tests 6 and 8]

## Tests

### 1. 64x22 Account Tab Row
expected: Open an SSH terminal session at exactly 64x22, sign in as a user with access to Account, and open Account. The rightmost tab-row column aligns with the screen frame vertical border, no trailing border glyphs render to the right of the rightmost tab, and the tab row remains inside the frame.
result: pass

### 2. 64x22 Moderation LOG Tab Row and Primary Table
expected: Open an SSH terminal session at exactly 64x22, sign in as a moderator or sysop, open Moderation, switch to LOG, and inspect the tab row and table. The tab row aligns with the frame with no trailing border glyph artifacts, LOG primary table rows remain inside the frame and above the command bar, and the table remains readable and navigable at compact height.
result: pass

### 3. 64x22 Moderation USERS Tab Row and Primary Table
expected: Open an SSH terminal session at exactly 64x22, sign in as a moderator or sysop, open Moderation, switch to USERS, and inspect the tab row and table. The tab row aligns with the frame with no trailing border glyph artifacts, USERS primary table rows remain inside the frame and above the command bar, and the table remains readable and navigable at compact height.
result: pass

### 4. 64x22 Moderation BOARDS Tab Row and Primary Table
expected: Open an SSH terminal session at exactly 64x22, sign in as a moderator or sysop, open Moderation, switch to BOARDS, and inspect the tab row and table. The tab row aligns with the frame with no trailing border glyph artifacts, BOARDS primary table rows remain inside the frame and above the command bar, and the table remains readable and navigable at compact height.
result: pass

### 5. 64x22 Sysop Tab Row
expected: Open an SSH terminal session at exactly 64x22, sign in as a sysop, and open Sysop. The rightmost tab-row column aligns with the screen frame vertical border, no trailing border glyphs render to the right of the rightmost tab, and the tab row remains inside the frame.
result: pass

### 6. 64x22 Boards Overlarge Directory
expected: Open an SSH terminal session at exactly 64x22, use a dataset with enough categories and boards to exceed the visible body, and open Boards. Category and board rows remain inside the screen frame, no list rows draw above the top border or below the command bar, and selection remains visible while navigating through the overlarge directory.
result: pending
reported: "Automated regression coverage now passes for overlarge 64x22 Boards density and navigation (`test/foglet_bbs/tui/screens/board_list_test.exs`, `test/foglet_bbs/tui/layout_smoke_test.exs`). The exact SSH rerun at 64x22 was not executed in this session, so human confirmation is still pending."
severity: human_needed

### 7. 80x24 Sysop INVITES With Available, Consumed, Revoked Rows
expected: Open an SSH terminal session at exactly 80x24, sign in as a sysop, and open Sysop INVITES with representative available, consumed, and revoked invite rows. Code, Status, Created, and Used by columns are visibly separated, values do not overlap or concatenate across column boundaries, and available, consumed, and revoked states are readable.
result: pass

### 8. 80x24 Moderation LOG With Long Body/Reason and Non-UTC User Timezone
expected: Open an SSH terminal session at exactly 80x24, sign in as a moderator or sysop with a non-UTC IANA timezone preference, and open Moderation LOG with a representative long body or reason field. The LOG table consumes available body width without crossing the frame, long body or reason text elides with `...` or `…` at cell boundaries, and the timestamp reflects the current user's configured non-UTC timezone.
result: pending
reported: "Automated regression coverage now passes for the shared width-allocation fix and Moderation LOG timezone/rendering behavior (`test/foglet_bbs/tui/widgets/display/table_test.exs`, `test/foglet_bbs/tui/widgets/display/console_table_test.exs`, `test/foglet_bbs/tui/screens/moderation_test.exs`). The exact SSH rerun at 80x24 was not executed in this session, so human confirmation is still pending."
severity: human_needed

### 9. Post Reader Paragraph Breaks
expected: Open an SSH terminal session and open a post reader view for a post containing the fixture body `soft`, `break`, blank line, `First`, blank line, `Second`, three newlines, `Third`. `soft` and `break` render as adjacent physical lines with no blank line between them, `First` and `Second` render with exactly one blank visible line between them, `Second` and `Third` render with exactly one blank visible line between them even though the source has three newline separators, and no literal `\n` text appears in the post body.
result: pass

## Summary

total: 9
passed: 7
issues: 0
pending: 2
skipped: 0
blocked: 0

## Gaps
- truth: "Boards category and board rows remain inside the screen frame and the overlarge directory remains navigable at 64x22."
  status: human_needed
  reason: "Automated regression coverage now passes for overlarge 64x22 Boards density and navigation, but the exact fixed-size SSH rerun was not executed in this session."
  severity: human_needed
  test: 6
  root_cause: "BoardList is reserving space for feedback, detail, and inspector rows before rendering the tree, then passing a small visible-height budget into BoardTree. The resulting window leaves the compact directory underfilled and the board rows do not occupy the body the way the smoke contract expects."
  artifacts:
    - path: "lib/foglet_bbs/tui/screens/board_list.ex"
      issue: "Current compact tree budgeting matches the density regression coverage; manual SSH confirmation is still pending."
    - path: "lib/foglet_bbs/tui/widgets/list/board_tree.ex"
      issue: "Current visible-row windowing remains the path that keeps focused rows in view during navigation."
  missing:
    - "Re-run the exact 64x22 SSH Boards scenario and record the human outcome."
  debug_session: ""
- truth: "The Moderation LOG table uses the available 80x24 width responsively so visible columns stretch enough to show more complete values when space is available."
  status: human_needed
  reason: "Automated regression coverage now passes for the shared table-width allocator and representative Moderation LOG rendering, but the exact fixed-size SSH rerun was not executed in this session."
  severity: human_needed
  test: 8
  root_cause: "Shared table columns were treating integer widths as hard caps, so value-bearing columns could leave usable width stranded instead of growing when extra space existed."
  artifacts:
    - path: "lib/foglet_bbs/tui/screens/moderation/state.ex"
      issue: "LOG value columns now opt into the shared growth contract so extra width goes to Body/Reason first."
    - path: "lib/foglet_bbs/tui/widgets/display/table.ex"
      issue: "Shared allocator now supports `grow` weights and keeps remainder allocation on growth columns instead of stranding width."
  missing:
    - "Re-run the exact 80x24 SSH Moderation LOG scenario and record the human outcome."
  debug_session: ""
