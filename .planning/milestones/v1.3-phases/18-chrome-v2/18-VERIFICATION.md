---
phase: 18-chrome-v2
verified: 2026-04-25T17:54:43Z
status: human_needed
score: 6/6 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Real terminal visual pass across migrated screens"
    expected: "Login, Home, Boards, thread flow, composer flow, Account, Moderation, and Sysop all show coherent breadcrumb chrome, right-side status, and grouped commands in an SSH terminal without visual crowding."
    why_human: "Automated render-tree and positioned layout checks verify structure and bounds, but terminal visual appearance still needs human inspection."
  - test: "Keyboard flow smoke through Chrome V2 screens"
    expected: "Existing hotkeys still navigate and act as before while command hints stay consistent with the active screen."
    why_human: "Unit tests cover key handlers, but end-to-end interaction feel over the SSH/TUI runtime is a user-flow check."
---

# Phase 18: Chrome V2 Verification Report

**Phase Goal:** Every screen shares breadcrumb chrome, mode-aware status, and grouped key commands.
**Verified:** 2026-04-25T17:54:43Z
**Status:** human_needed
**Re-verification:** No - initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Users see breadcrumb-style locations rooted at `Foglet`, with Unicode and ASCII fallback. | VERIFIED | `BreadcrumbBar.parts_for/1`, `format/2`, and `render/3` exist; named screens resolve centrally, `format/2` supports `" ▸ "` and `ascii?: true` `" > "`, and delegates width clipping to `TextWidth.truncate/2`. |
| 2 | Users see mode-appropriate right status fields for BBS and operator screens. | VERIFIED | `StatusBar.status_atoms/1` calls `Presentation.mode_for!/1`; BBS atoms include handle/unread/activity/time when present, operator atoms include handle/scope/system/time when present, and guests render `guest` only. |
| 3 | `Chrome.CommandBar` groups commands and truncates lower-priority hints inside the frame. | VERIFIED | `CommandBar.normalize_groups/1` sorts by priority; `visible_groups/2` drops highest numeric priority first; all width work uses `TextWidth.display_width/1` and `TextWidth.truncate/2`. |
| 4 | Existing simple key-list callers render through `Chrome.CommandBar`, not a parallel footer. | VERIFIED | `KeyBar.render/3` delegates to `Normalizer.commands/1` and `CommandBar.render/3`; `ScreenFrame` uses `CommandBar` and `Normalizer`; static test proves no production screen calls `KeyBar.render`. |
| 5 | Login declares Classic Modern BBS mode and receives Chrome V2 without changing auth behavior. | VERIFIED | `Presentation.mode_for!(:login) == :bbs` is tested; `Login.render/1` still calls `ScreenFrame.render/4`; login behavior tests were included in the local focused gate. |
| 6 | Chrome remains usable at 64x22, 80x24, and wide sizes without overlap/content displacement. | VERIFIED | `layout_smoke_test.exs` covers `{64,22}`, `{80,24}`, and `{132,50}` through `Raxol.UI.Layout.Engine.apply_layout/2`, asserting text bounds and top/content/command y-ordering. |

**Score:** 6/6 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex` | Shared breadcrumb resolver/formatter | VERIFIED | Exists, substantive, wired through `ScreenFrame`; review warning fixed by using `Moderation.State.tab_labels(true)`. |
| `lib/foglet_bbs/tui/widgets/chrome/status_bar.ex` | Mode-aware status atoms/top chrome | VERIFIED | Exists, substantive, wired through `ScreenFrame`; optional atoms are honest and not fabricated. |
| `lib/foglet_bbs/tui/widgets/chrome/command_bar.ex` | Grouped command renderer | VERIFIED | Exists, substantive, wired through `ScreenFrame` and `KeyBar` compatibility path. |
| `lib/foglet_bbs/tui/widgets/chrome/normalizer.ex` | Legacy key-list adapter | VERIFIED | Exists, substantive, feeds normalized command groups into `CommandBar`. |
| `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex` | Compatibility wrapper only | VERIFIED | Delegates directly to `CommandBar.render/3`; no separate footer implementation remains. |
| `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` | Single Chrome V2 composition boundary | VERIFIED | Composes `StatusBar`, content, divider, and `CommandBar` inside the outer frame. |
| Named screen modules | Chrome V2 callers | VERIFIED | Login, MainMenu, BoardList, ThreadList, PostReader, NewThread, PostComposer, Account, Moderation, and Sysop call `ScreenFrame.render/4`. |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `StatusBar` | `Presentation` | `Presentation.mode_for!/1` | WIRED | Mode is resolved from `state.current_screen`, not role/theme. |
| `BreadcrumbBar` | `TextWidth` | `TextWidth.truncate/2` | WIRED | Width-limited formatting delegates to the shared width helper. |
| `ScreenFrame` | `BreadcrumbBar`, `StatusBar`, `CommandBar`, `Normalizer` | Chrome model normalization/render | WIRED | `screen_frame.ex` aliases and calls all Chrome V2 primitives; no `KeyBar` dependency. |
| `KeyBar` | `CommandBar` | Compatibility adapter | WIRED | `KeyBar.render/3` calls `Normalizer.commands(keys)` then `CommandBar.render/3`. |
| Screens | `ScreenFrame` | `ScreenFrame.render/4` | WIRED | All named phase screens call the shared frame boundary. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|---|---|---|---|---|
| `BreadcrumbBar` | breadcrumb parts | `current_screen`, `current_board`, `current_thread`, `screen_state` tab state | Yes | FLOWING |
| `StatusBar` | status atoms | `current_user`, `unread_count`, `activity_label`, `operator_scope`, `system_status`, `session_context.clock_now` | Yes | FLOWING |
| `CommandBar` | command groups | grouped caller data or legacy key tuples through `Normalizer` | Yes | FLOWING |
| `ScreenFrame` | chrome model | state plus caller title/chrome map plus command list | Yes | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Chrome primitives render/normalize as specified | `rtk mix test test/foglet_bbs/tui/widgets/chrome/breadcrumb_test.exs test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs test/foglet_bbs/tui/widgets/chrome/command_bar_test.exs test/foglet_bbs/tui/widgets/chrome/normalizer_test.exs test/foglet_bbs/tui/widgets/chrome/screen_frame_test.exs` | 32 tests, 0 failures | PASS |
| Migrated screens and layout smoke remain green | `rtk mix test test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/screens/thread_list_test.exs test/foglet_bbs/tui/screens/post_reader_test.exs test/foglet_bbs/tui/screens/new_thread_test.exs test/foglet_bbs/tui/screens/post_composer_test.exs test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/tui/presentation_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` | 356 tests, 0 failures | PASS |
| Review warning fix present | `rtk rg "ModerationState.tab_labels|Foglet ▸ Moderation ▸ LOG"` | Resolver and regression test found | PASS |
| Legacy footer closure | `rtk rg "KeyBar.render" lib/foglet_bbs/tui` | No production calls outside compatibility module | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| CHROME-01 | 18-01, 18-03, 18-04, 18-05, 18-06, 18-07 | Shared breadcrumb-style locations with ASCII fallback | SATISFIED | `BreadcrumbBar` central resolver/formatter plus screen render tests for all named screens. |
| CHROME-02 | 18-01, 18-03, 18-04, 18-05, 18-06, 18-07 | Mode-appropriate right-side status fields | SATISFIED | `StatusBar.status_atoms/1` uses `Presentation.mode_for!/1`; BBS/operator/guest tests pass. |
| CHROME-03 | 18-02, 18-03, 18-04, 18-05, 18-06, 18-07 | Grouped commands and priority truncation | SATISFIED | `CommandBar` grouping/truncation tests pass; `ScreenFrame` renders it inside the frame. |
| CHROME-04 | 18-03 through 18-07 | Usable at 64x22, 80x24, and wider sizes | SATISFIED | Positioned layout smoke tests cover required sizes and text bounds. |
| CHROME-05 | 18-02, 18-07 | Existing footer path migrated through compatibility adapter | SATISFIED | `KeyBar` is delegation-only; source-level tests guard no production `KeyBar.render` calls. |
| LOGIN-01 | 18-04 | Login declares BBS mode and receives Chrome V2 without auth changes | SATISFIED | Login render/mode tests and existing login behavior tests pass. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| `lib/foglet_bbs/tui/screens/moderation.ex` | 64 | `"Moderation is not available."` | Info | Honest defensive unauthorized state; pre-existing operator posture, not a Phase 18 stub. |
| `lib/foglet_bbs/tui/screens/sysop.ex` | 70, 115-143 | unavailable/load placeholder copy | Info | Existing lazy-load/read-only operator behavior explicitly out of Phase 18 scope. |
| `lib/foglet_bbs/tui/widgets/chrome/status_bar.ex` | 101 | legacy `"Foglet BBS —"` path | Info | Compatibility for direct `StatusBar.render/2`; `ScreenFrame` passes Chrome V2 model data. |

### Human Verification Required

### 1. Real Terminal Visual Pass

**Test:** Open the SSH/TUI experience and visit Login, Home, Boards, thread flow, composer flow, Account, Moderation, and Sysop at representative terminal sizes.
**Expected:** Breadcrumb chrome, right status atoms, grouped commands, and content are visually coherent with no crowding or misleading command placement.
**Why human:** Automated layout tests check bounds and ordering, but real terminal visual appearance is a human-verification category.

### 2. Keyboard Flow Smoke

**Test:** Use the visible command hints to navigate the migrated screens and perform existing non-destructive flows.
**Expected:** Existing key behavior matches prior tests while hints remain accurate for each active screen.
**Why human:** Unit tests cover handlers, but end-to-end SSH/TUI interaction flow still needs human confirmation.

### Gaps Summary

No automated gaps found. All roadmap and plan must-haves are implemented, substantive, wired, and covered by focused tests. Status is `human_needed` only because final terminal visual/user-flow inspection cannot be fully proven from static and ExUnit checks.

---

_Verified: 2026-04-25T17:54:43Z_
_Verifier: Claude (gsd-verifier)_
