---
status: testing
phase: 26-layout-width-foundations
source:
  - .planning/phases/26-layout-width-foundations/26-01-SUMMARY.md
  - .planning/phases/26-layout-width-foundations/26-02-SUMMARY.md
  - .planning/phases/26-layout-width-foundations/26-03-SUMMARY.md
  - .planning/phases/26-layout-width-foundations/26-04-SUMMARY.md
started: 2026-04-26T22:32:00Z
updated: 2026-04-26T23:31:00Z
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

number: 5
name: 64x22 Sysop Tab Row
expected: |
  Open an SSH terminal session at exactly 64x22, sign in as a sysop, and open Sysop. The rightmost tab-row column aligns with the screen frame vertical border, no trailing border glyphs render to the right of the rightmost tab, and the tab row remains inside the frame.
awaiting: user response

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
result: [pending]

### 6. 64x22 Boards Overlarge Directory
expected: Open an SSH terminal session at exactly 64x22, use a dataset with enough categories and boards to exceed the visible body, and open Boards. Category and board rows remain inside the screen frame, no list rows draw above the top border or below the command bar, and selection remains visible while navigating through the overlarge directory.
result: [pending]

### 7. 80x24 Sysop INVITES With Available, Consumed, Revoked Rows
expected: Open an SSH terminal session at exactly 80x24, sign in as a sysop, and open Sysop INVITES with representative available, consumed, and revoked invite rows. Code, Status, Created, and Used by columns are visibly separated, values do not overlap or concatenate across column boundaries, and available, consumed, and revoked states are readable.
result: pass

### 8. 80x24 Moderation LOG With Long Body/Reason and Non-UTC User Timezone
expected: Open an SSH terminal session at exactly 80x24, sign in as a moderator or sysop with a non-UTC IANA timezone preference, and open Moderation LOG with a representative long body or reason field. The LOG table consumes available body width without crossing the frame, long body or reason text elides with `...` or `…` at cell boundaries, and the timestamp reflects the current user's configured non-UTC timezone.
result: [pending]

### 9. Post Reader Paragraph Breaks
expected: Open an SSH terminal session and open a post reader view for a post containing the fixture body `soft`, `break`, blank line, `First`, blank line, `Second`, three newlines, `Third`. `soft` and `break` render as adjacent physical lines with no blank line between them, `First` and `Second` render with exactly one blank visible line between them, `Second` and `Third` render with exactly one blank visible line between them even though the source has three newline separators, and no literal `\n` text appears in the post body.
result: pass

## Summary

total: 9
passed: 5
passed: 6
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps

- truth: "The Account tab row ends cleanly at the last tab without a trailing border glyph inside the screen frame."
  status: failed
  reason: "User reported a trailing boxed edge after the tab row in the 64x22 Account view."
  severity: cosmetic
  test: 1
  root_cause: "The Account tab strip is still rendered as a boxed container, so the inner right border remains visible at the end of the row instead of the row ending flush with the last tab label."
  artifacts:
    - path: "lib/foglet_bbs/tui/widgets/input/tabs.ex"
      issue: "Tabs.render/2 wraps the strip in a box even when the layout contract wants a borderless row edge."
    - path: "lib/foglet_bbs/tui/screens/account.ex"
      issue: "Account forwards drawable width correctly, so the remaining artifact is in the tab widget rendering contract."
  missing:
    - "Decide whether Account tabs should render as a plain row or shrink one more column so the inner box edge is hidden."
    - "Add a regression test that asserts the right edge of the Account tab row does not expose a border glyph at compact width."
  debug_session: ""
- truth: "The Sysop tab row ends cleanly at the last tab without a trailing border glyph inside the screen frame."
  status: failed
  reason: "User reported the Sysop tab strip still ends with a visible border glyph after the last tab."
  severity: cosmetic
  test: 5
  root_cause: "The Sysop tab strip uses the same boxed tab widget contract as Account, so the inner right border remains visible at the end of the row."
  artifacts:
    - path: "lib/foglet_bbs/tui/widgets/input/tabs.ex"
      issue: "Tabs.render/2 always wraps the tab strip in a box, exposing the right border glyph at compact widths."
    - path: "lib/foglet_bbs/tui/screens/sysop.ex"
      issue: "Sysop forwards drawable width into Tabs correctly, so the artifact is in shared rendering."
  missing:
    - "Choose a borderless or edge-trimmed rendering path for compact tab rows."
    - "Add a regression test for Sysop tab rows at compact width."
  debug_session: ""
- truth: "Boards category and board rows remain inside the screen frame and the overlarge directory remains navigable at 64x22."
  status: failed
  reason: "User reported a Boards view with large blank spans and only partial directory rows visible, ending at the command bar."
  severity: major
  test: 6
  root_cause: "BoardList is reserving space for feedback, detail, and inspector rows before rendering the tree, then passing a small visible-height budget into BoardTree. The resulting window leaves the compact directory underfilled and the board rows do not occupy the body the way the smoke contract expects."
  artifacts:
    - path: "lib/foglet_bbs/tui/screens/board_list.ex"
      issue: "render_board_content/3 computes reserved_rows and visible_height in a way that can under-allocate the tree on compact screens."
    - path: "lib/foglet_bbs/tui/widgets/list/board_tree.ex"
      issue: "BoardTree renders newline-separated rows, so the screen-level budget needs to account for separator rows precisely."
  missing:
    - "Revisit the compact Boards height budget so the tree gets the intended share of the frame."
    - "Add or tighten a smoke assertion for visible row density on 64x22 Boards."
  debug_session: ""
- truth: "The Moderation LOG timestamp reflects the current user's configured 12-hour time preference."
  status: failed
  reason: "User reported the log timestamp stayed in 24-hour format despite a 12-hour preference."
  severity: major
  test: 8
  root_cause: "Moderation log timestamps are formatted with a fixed `Calendar.strftime(..., \"%m-%d %H:%M\")` pattern in `Moderation.State.format_log_timestamp/2`, so the screen ignores the user's 12-hour preference entirely."
  artifacts:
    - path: "lib/foglet_bbs/tui/screens/moderation/state.ex"
      issue: "format_log_timestamp/2 hardcodes 24-hour formatting instead of reusing the preference-aware clock formatter."
    - path: "lib/foglet_bbs/tui/widgets/chrome/clock_formatter.ex"
      issue: "This is the existing preference-aware formatter that already handles timezone and 12h/24h settings."
  missing:
    - "Route moderation log timestamps through the shared preference-aware clock formatter or equivalent helper."
    - "Add a regression test covering a 12-hour preference on the Moderation LOG tab."
  debug_session: ""
