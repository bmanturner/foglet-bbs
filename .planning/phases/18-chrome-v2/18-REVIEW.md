---
phase: 18-chrome-v2
reviewed: 2026-04-25T17:49:59Z
depth: standard
files_reviewed: 35
files_reviewed_list:
  - lib/foglet_bbs/tui/presentation.ex
  - lib/foglet_bbs/tui/screens/account.ex
  - lib/foglet_bbs/tui/screens/board_list.ex
  - lib/foglet_bbs/tui/screens/login.ex
  - lib/foglet_bbs/tui/screens/main_menu.ex
  - lib/foglet_bbs/tui/screens/moderation.ex
  - lib/foglet_bbs/tui/screens/new_thread.ex
  - lib/foglet_bbs/tui/screens/post_composer.ex
  - lib/foglet_bbs/tui/screens/post_reader.ex
  - lib/foglet_bbs/tui/screens/sysop.ex
  - lib/foglet_bbs/tui/screens/thread_list.ex
  - lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex
  - lib/foglet_bbs/tui/widgets/chrome/command_bar.ex
  - lib/foglet_bbs/tui/widgets/chrome/key_bar.ex
  - lib/foglet_bbs/tui/widgets/chrome/normalizer.ex
  - lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex
  - lib/foglet_bbs/tui/widgets/chrome/status_bar.ex
  - test/foglet_bbs/tui/layout_smoke_test.exs
  - test/foglet_bbs/tui/presentation_test.exs
  - test/foglet_bbs/tui/screens/account_test.exs
  - test/foglet_bbs/tui/screens/board_list_test.exs
  - test/foglet_bbs/tui/screens/login_test.exs
  - test/foglet_bbs/tui/screens/main_menu_test.exs
  - test/foglet_bbs/tui/screens/moderation_test.exs
  - test/foglet_bbs/tui/screens/new_thread_test.exs
  - test/foglet_bbs/tui/screens/post_composer_test.exs
  - test/foglet_bbs/tui/screens/post_reader_test.exs
  - test/foglet_bbs/tui/screens/sysop_test.exs
  - test/foglet_bbs/tui/screens/thread_list_test.exs
  - test/foglet_bbs/tui/widgets/chrome/breadcrumb_test.exs
  - test/foglet_bbs/tui/widgets/chrome/command_bar_test.exs
  - test/foglet_bbs/tui/widgets/chrome/key_bar_test.exs
  - test/foglet_bbs/tui/widgets/chrome/normalizer_test.exs
  - test/foglet_bbs/tui/widgets/chrome/screen_frame_test.exs
  - test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs
findings:
  critical: 0
  warning: 1
  info: 0
  total: 1
status: issues_found
---

# Phase 18: Code Review Report

**Reviewed:** 2026-04-25T17:49:59Z
**Depth:** standard
**Files Reviewed:** 35
**Status:** issues_found

## Summary

Reviewed the Chrome V2 presentation, screen-frame, status, command, breadcrumb, keybar, and listed screen/test changes at standard depth. The main implementation is well-scoped, but the shared breadcrumb tab-label mapping has drifted from the actual operator screen state and can render incorrect location text for Moderation active tabs.

## Warnings

### WR-01: Shared Moderation Breadcrumb Tab Labels Are Stale

**File:** `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex:21`

**Issue:** `BreadcrumbBar` hard-codes operator tab labels that do not match the real tab contracts. `@moderation_tabs` is `["Queue", "Oneliners", "Invites"]`, while `Foglet.TUI.Screens.Moderation.State` exposes `["QUEUE", "LOG", "USERS", "SANCTIONS", "BOARDS"]` plus optional `"INVITES"`. Because `Moderation.render/1` passes `moderation_chrome()` without explicit `:breadcrumb_parts`, `ScreenFrame` falls back to `BreadcrumbBar.parts_for/1`; active tab 1 will render `Foglet ▸ Moderation ▸ Oneliners` even though the selected tab is `LOG`, active tab 2 renders `Invites` instead of `USERS`, and later tabs lose the active tab segment entirely. Existing tests only assert the default Moderation breadcrumb, so this regression is not covered.

**Fix:**
Use the real state modules as the breadcrumb source of truth, or pass explicit breadcrumb parts from `Moderation.render/1` the way `Sysop` already does. Add tests for non-zero active tabs.

```elixir
# Prefer deriving from the screen state module instead of duplicating labels.
alias Foglet.TUI.Screens.Moderation.State, as: ModerationState

defp tabs_for(:moderation), do: ModerationState.tab_labels(true)
```

For a lower-risk local fix, change `Moderation` to build its chrome from the synced screen state:

```elixir
ScreenFrame.render(
  state,
  %{breadcrumb_parts: ["Foglet", "Moderation", active_label]},
  content,
  @key_list
)
```

Then add a regression assertion such as `active_tab: 1` rendering `Foglet ▸ Moderation ▸ LOG`.

---

_Reviewed: 2026-04-25T17:49:59Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
