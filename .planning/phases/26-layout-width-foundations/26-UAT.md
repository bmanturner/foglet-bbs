---
status: partial
phase: 26-layout-width-foundations
source:
  - .planning/phases/26-layout-width-foundations/26-01-SUMMARY.md
  - .planning/phases/26-layout-width-foundations/26-02-SUMMARY.md
  - .planning/phases/26-layout-width-foundations/26-03-SUMMARY.md
  - .planning/phases/26-layout-width-foundations/26-04-SUMMARY.md
started: 2026-04-26T22:32:00Z
updated: 2026-04-27T00:25:00Z
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

[automated render reconciliation complete; exact SSH rerun still pending for test 8]

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
result: pass

### 7. 80x24 Sysop INVITES Shared Table Contract
expected: Open an SSH terminal session at exactly 80x24, sign in as a sysop, and open Sysop INVITES with representative available, consumed, and revoked invite rows. If the visible Code, Status, Created, and Used by values fit inside the framed width budget, the full values render with no unnecessary truncation. If they do not all fit, Code yields last, lower-priority metadata columns yield first, and values remain visibly separated with no overlap or concatenation.
result: pending
reported: "The shared widget regression suite now proves the intended contract: full visible values render when they fit, low-priority empty columns do not reserve width, and lower-priority columns sacrifice width before Code. The exact 80x24 Sysop INVITES SSH rerun was not repeated in this execution session after the shared allocator change, so the human-visible outcome remains pending."
severity: human_needed

### 8. 80x24 Shared Table Contract With Moderation LOG and Non-UTC User Timezone
expected: Open an SSH terminal session at exactly 80x24, sign in as a moderator or sysop with a non-UTC IANA timezone preference, and open Moderation LOG with a representative long body or reason field. The shared table widget consumes available body width without crossing the frame, shows full visible values when the current row content fits, elides long body or reason text with `...` or `…` at cell boundaries when it does not, and preserves the timestamp in the current user's configured non-UTC timezone.
result: pending
reported: "The current workspace automation and direct `State.build_log_table/2` render check no longer match the stale failure snapshot. With an 80x24 session budget (`width: 76` inside the frame), the shared allocator now resolves widths from content demand and column priority, keeps the timestamp in the user's timezone (`04-24 08:05 AM` in the representative check), and truncates long values at cell boundaries. The exact SSH rerun from the user's terminal has not been repeated in this execution session, so the human-visible outcome remains pending."
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
- truth: "The Moderation LOG table uses the available 80x24 width responsively so visible columns stretch enough to show more complete values when space is available."
  status: human_needed
  reason: "The current workspace render and regression suite show the shared-width fix is present, but the exact 80x24 SSH rerun from the user's terminal has not been repeated in this session."
  severity: human_needed
  test: 8
  root_cause: "The earlier SSH snapshot was captured before the current shared-width allocator and Moderation LOG growth metadata were reconciled. The remaining uncertainty is human verification of the exact terminal render, not a known missing allocator fix in the workspace."
  artifacts:
    - path: "lib/foglet_bbs/tui/screens/moderation/state.ex"
      issue: "Current LOG column definitions resolve to wider Body and Reason columns under the shared growth contract."
    - path: "lib/foglet_bbs/tui/widgets/display/table.ex"
      issue: "Current shared allocator routes surplus width into growth columns and preserves truncation at cell boundaries."
  missing:
    - "Re-run the exact 80x24 SSH Moderation LOG scenario and record the human outcome."
  debug_session: ""
- truth: "The Sysop INVITES table shows the full Code value whenever the visible row values fit inside the 80x24 framed width budget, and only sacrifices lower-priority metadata columns first when they do not."
  status: human_needed
  reason: "The shared-widget regression suite proves the allocator contract, but the exact 80x24 Sysop INVITES SSH rerun was not repeated in this session after the allocator changed."
  severity: human_needed
  test: 7
  root_cause: "Previous Phase 26 evidence only proved column separation. This gap closure broadened the acceptance target to full-value visibility when width permits, which still needs live SSH confirmation."
  artifacts:
    - path: "lib/foglet_bbs/tui/widgets/display/table.ex"
      issue: "The shared allocator now sizes from content demand and column priority instead of static width/grow heuristics alone."
    - path: "lib/foglet_bbs/tui/screens/shared/invites_state.ex"
      issue: "INVITES now declares Code as the highest-priority content-aware column while Used by yields when empty or lower-value."
  missing:
    - "Re-run the exact 80x24 SSH Sysop INVITES scenario with available, consumed, and revoked rows and record whether full Code remains visible when the visible values fit."
  debug_session: ""
