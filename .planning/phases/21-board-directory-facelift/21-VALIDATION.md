---
phase: 21
slug: board-directory-facelift
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-25
---

# Phase 21 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (Elixir/Phoenix) |
| **Config file** | mix.exs / config/test.exs |
| **Quick run command** | `rtk mix test --only board_directory` |
| **Full suite command** | `rtk mix test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `rtk mix test --only board_directory`
- **After every plan wave:** Run `rtk mix test`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| TBD     | TBD  | TBD  | BOARDS-01   | —          | N/A             | unit      | `rtk mix test --only board_directory` | ❌ W0 | ⬜ pending |
| TBD     | TBD  | TBD  | BOARDS-02   | —          | N/A             | unit      | `rtk mix test --only board_directory` | ❌ W0 | ⬜ pending |
| TBD     | TBD  | TBD  | BOARDS-03   | —          | N/A             | unit      | `rtk mix test --only board_directory` | ❌ W0 | ⬜ pending |
| TBD     | TBD  | TBD  | BOARDS-04   | —          | N/A             | unit      | `rtk mix test --only board_directory` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

*Planner will populate Task IDs and Plan numbers after PLAN.md generation.*

---

## Wave 0 Requirements

- [ ] `test/foglet_bbs/tui/screens/board_directory_test.exs` — screen-level rendering tests for category/board rows
- [ ] `test/foglet_bbs/tui/widgets/board_tree_test.exs` — widget tests for tree rows with semantic columns
- [ ] Confirm existing `test/foglet_bbs/tui/widgets/rich_row_test.exs` and `test/foglet_bbs/tui/theme_test.exs` cover row primitives

*Existing ExUnit infrastructure covers TUI tests; no framework install needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Visual layout at 64×22 terminal width | BOARDS-03 | Visual rendering / terminal-specific layout cannot be asserted via snapshot alone | SSH into local BBS at `stty cols 64 rows 22`, navigate to board directory, confirm compact details strip is visible and not truncated |
| Visual layout at wide terminal (120+ cols) | BOARDS-03 | Wide inspector activation depends on real terminal width detection | SSH into local BBS in a wide terminal, navigate to board directory, confirm wide inspector renders with detail panes |
| Subscribe/open/back keybinding flow | BOARDS-04 | Interactive keystroke handling end-to-end | Navigate to board directory, press `s` to toggle subscription, `enter` to open board, `escape` to back out — confirm state transitions are correct |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
