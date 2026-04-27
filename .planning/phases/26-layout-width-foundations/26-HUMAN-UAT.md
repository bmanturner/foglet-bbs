---
phase: 26
started: 2026-04-26
updated: 2026-04-26
status: pending
---

# Phase 26 Human SSH UAT

Manual SSH terminal verification is pending. This execution session created the checklist and ran automated checks, but did not run real SSH visual verification at fixed terminal sizes.

## Scenario Status Values

Use one of: `pending`, `pass`, `fail`.

## Scenarios

### 64x22 Account Tab Row

Status: pending

Requirement mapping: LAYOUT-01.

Steps:
- Open an SSH terminal session at exactly 64x22.
- Sign in as a user with access to Account.
- Open Account and inspect the tab row.

Expected:
- The rightmost tab-row column aligns with the screen frame vertical border.
- No trailing border glyphs render to the right of the rightmost tab.
- The tab row remains inside the frame.

Result notes:
- Pending manual SSH verification. Automated regression coverage now passes for compact overlarge-directory density and navigation in `test/foglet_bbs/tui/screens/board_list_test.exs` and `test/foglet_bbs/tui/layout_smoke_test.exs`.

### 64x22 Moderation LOG Tab Row and Primary Table

Status: pending

Requirement mapping: LAYOUT-01, LAYOUT-02.

Steps:
- Open an SSH terminal session at exactly 64x22.
- Sign in as a moderator or sysop.
- Open Moderation, switch to LOG, and inspect the tab row and table.

Expected:
- The tab row aligns with the frame with no trailing border glyph artifacts.
- LOG primary table rows remain inside the frame and above the command bar.
- The table remains readable and navigable at compact height.

Result notes:
- Pending manual SSH verification. Automated regression coverage now passes for the shared table-width fix and representative Moderation LOG rendering in `test/foglet_bbs/tui/widgets/display/table_test.exs`, `test/foglet_bbs/tui/widgets/display/console_table_test.exs`, and `test/foglet_bbs/tui/screens/moderation_test.exs`.

### 64x22 Moderation USERS Tab Row and Primary Table

Status: pending

Requirement mapping: LAYOUT-01, LAYOUT-02.

Steps:
- Open an SSH terminal session at exactly 64x22.
- Sign in as a moderator or sysop.
- Open Moderation, switch to USERS, and inspect the tab row and table.

Expected:
- The tab row aligns with the frame with no trailing border glyph artifacts.
- USERS primary table rows remain inside the frame and above the command bar.
- The table remains readable and navigable at compact height.

Result notes:
- Pending manual SSH verification.

### 64x22 Moderation BOARDS Tab Row and Primary Table

Status: pending

Requirement mapping: LAYOUT-01, LAYOUT-02.

Steps:
- Open an SSH terminal session at exactly 64x22.
- Sign in as a moderator or sysop.
- Open Moderation, switch to BOARDS, and inspect the tab row and table.

Expected:
- The tab row aligns with the frame with no trailing border glyph artifacts.
- BOARDS primary table rows remain inside the frame and above the command bar.
- The table remains readable and navigable at compact height.

Result notes:
- Pending manual SSH verification.

### 64x22 Sysop Tab Row

Status: pending

Requirement mapping: LAYOUT-01.

Steps:
- Open an SSH terminal session at exactly 64x22.
- Sign in as a sysop.
- Open Sysop and inspect the tab row.

Expected:
- The rightmost tab-row column aligns with the screen frame vertical border.
- No trailing border glyphs render to the right of the rightmost tab.
- The tab row remains inside the frame.

Result notes:
- Pending manual SSH verification.

### 64x22 Boards Overlarge Directory

Status: pending

Requirement mapping: LAYOUT-03.

Steps:
- Open an SSH terminal session at exactly 64x22.
- Use a dataset with enough categories and boards to exceed the visible body.
- Open Boards and navigate through the category and board tree.

Expected:
- Category and board rows remain inside the screen frame.
- No list rows draw above the top border or below the command bar.
- Selection remains visible while navigating through the overlarge directory.

Result notes:
- Pending manual SSH verification.

### 80x24 Sysop INVITES With Available, Consumed, Revoked Rows

Status: pending

Requirement mapping: LAYOUT-04.

Steps:
- Open an SSH terminal session at exactly 80x24.
- Sign in as a sysop.
- Open Sysop INVITES with representative available, consumed, and revoked invite rows.

Expected:
- Code, Status, Created, and Used by columns are visibly separated.
- Values do not overlap or concatenate across column boundaries.
- Available, consumed, and revoked states are readable.

Result notes:
- Pending manual SSH verification.

### 80x24 Moderation LOG With Long Body/Reason and Non-UTC User Timezone

Status: pending

Requirement mapping: LAYOUT-05.

Steps:
- Open an SSH terminal session at exactly 80x24.
- Sign in as a moderator or sysop with a non-UTC IANA timezone preference.
- Open Moderation LOG with a representative long body or reason field.

Expected:
- The LOG table consumes available body width without crossing the frame.
- Long body or reason text elides with `...` or `…` at cell boundaries.
- The timestamp reflects the current user's configured non-UTC timezone.

Result notes:
- Pending manual SSH verification. The current workspace automation and direct render inspection now show the shared-width fix is present: `State.build_log_table/2` at the 80x24 framed width budget (`width: 76`) resolves `when=14`, `actor=9`, `action=9`, `body=24`, `reason=15`, keeps the timestamp in the user's timezone (`04-24 08:05 AM` in the representative check), and truncates long values at cell boundaries. The exact SSH rerun still needs a human verifier.

### Post Reader Paragraph Breaks

Status: pending

Requirement mapping: POST-01.

Post body fixture:

```text
soft
break

First

Second


Third
```

Steps:
- Open an SSH terminal session.
- Open a post reader view for a post containing the fixture body above.
- Inspect the rendered body.

Expected:
- `soft` and `break` render as adjacent physical lines with no blank line between them.
- `First` and `Second` render with exactly one blank visible line between them.
- `Second` and `Third` render with exactly one blank visible line between them, even though the source has three newline separators.
- No literal `\n` text appears in the post body.

Result notes:
- Pending manual SSH verification.

## Blocker

Manual SSH visual verification was not run in this execution session. All scenarios remain pending for a human verifier with a real terminal at the specified dimensions.

## Automated Verification

### `rtk mix test test/foglet_bbs/tui/text_width_test.exs test/foglet_bbs/tui/widgets/display/table_test.exs test/foglet_bbs/tui/widgets/display/console_table_test.exs`

Status: pass

Result:
- 52 tests, 0 failures.

### `rtk mix test test/foglet_bbs/tui/widgets/input/tabs_test.exs test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/widgets/post/markdown_body_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`

Status: pass

Result:
- 182 tests, 0 failures.

### `rtk mix precommit`

Status: fail

Result:
- Compile, formatter, Credo, and Sobelow completed.
- Dialyzer failed with 101 total errors, including pre-existing/out-of-scope warnings already documented by Phase 26 Plans 02 and 03.

Out-of-scope examples from the failure:
- `lib/foglet_bbs/mix_task_helpers.ex:44:7:no_return` for `fail/1`.
- `lib/foglet_bbs/tui/screens/login/state.ex` contract supertype warnings for `default/0`, `login_form/0`, `reset_request/0`, `toggle_focus/1`, and `input_key/1`.
- `lib/foglet_bbs/tui/screens/register/state.ex` contract supertype warnings for `default/0`, `clear/1`, and `input_key/1`.
- `lib/foglet_bbs/tui/screens/verify/state.ex` contract supertype warnings for `default/0`, `clear/1`, `cooldown?/1`, and `resend_cooldown?/1`.
- `lib/mix/tasks/foglet.board_subscriptions.ex:127:8:no_return` for `fail/1` and `fail/2`.
- `lib/mix/tasks/foglet.user.status.ex:92:8:no_return` for `fail/1`.

Phase 26 Plan 04 impact:
- No Dialyzer failures were reported for `lib/foglet_bbs/markdown.ex`, `lib/foglet_bbs/tui/widgets/post/markdown_body.ex`, or the Phase 26 layout/markdown test files changed by this plan.
