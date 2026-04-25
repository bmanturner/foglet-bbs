---
phase: 18
slug: chrome-v2
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-25
---

# Phase 18 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit via Mix |
| **Config file** | `mix.exs` |
| **Quick run command** | `rtk mix test test/foglet_bbs/tui/widgets/chrome test/foglet_bbs/tui/presentation_test.exs test/foglet_bbs/tui/text_width_test.exs` |
| **Full suite command** | `rtk mix precommit` |
| **Estimated runtime** | ~180 seconds |

---

## Sampling Rate

- **After every task commit:** Run the narrowest relevant `rtk mix test ...` command for the modified widget, screen, or layout smoke test file.
- **After every plan wave:** Run `rtk mix test test/foglet_bbs/tui/widgets/chrome test/foglet_bbs/tui/screens test/foglet_bbs/tui/layout_smoke_test.exs`.
- **Before `$gsd-verify-work`:** `rtk mix precommit` must be green.
- **Max feedback latency:** 180 seconds for narrow tests; full precommit may exceed this and is reserved for wave and phase completion.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 18-01-01 | 01 | 1 | CHROME-01 | T-18-01 | Breadcrumb render data is display-only and does not grant access. | unit | `rtk mix test test/foglet_bbs/tui/widgets/chrome/breadcrumb_test.exs` | W0 | pending |
| 18-01-02 | 01 | 1 | CHROME-02 | T-18-02 | Status atoms render scoped session data only. | unit | `rtk mix test test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs` | existing + W0 | pending |
| 18-02-01 | 02 | 1 | CHROME-03, CHROME-04 | T-18-03 | Command hints are passive affordances; mutation authorization remains in contexts. | unit | `rtk mix test test/foglet_bbs/tui/widgets/chrome/command_bar_test.exs` | W0 | pending |
| 18-03-01 | 03 | 2 | CHROME-01, CHROME-02, CHROME-03, CHROME-04 | T-18-04 | Screen chrome migration does not move domain decisions into render functions. | integration | `rtk mix test test/foglet_bbs/tui/screens test/foglet_bbs/tui/layout_smoke_test.exs` | existing + W0 | pending |
| 18-04-01 | 04 | 2 | LOGIN-01 | T-18-05 | Login remains render-only and does not change authentication behavior. | integration | `rtk mix test test/foglet_bbs/tui/screens/login_test.exs` | existing | pending |
| 18-05-01 | 05 | 3 | CHROME-05 | T-18-06 | Narrow terminal truncation avoids hiding content or commands needed for navigation. | layout | `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` | existing + W0 | pending |

---

## Wave 0 Requirements

- [ ] `test/foglet_bbs/tui/widgets/chrome/breadcrumb_test.exs` - stubs for CHROME-01 breadcrumb formatting, truncation, and ASCII fallback.
- [ ] `test/foglet_bbs/tui/widgets/chrome/command_bar_test.exs` - stubs for CHROME-03 and CHROME-04 grouped command rendering, priority truncation, and legacy key-list compatibility.
- [ ] `test/foglet_bbs/tui/widgets/chrome/screen_frame_test.exs` - stubs for CHROME-01 through CHROME-04 composition through `Chrome.ScreenFrame.render/4`.
- [ ] `test/foglet_bbs/tui/layout_smoke_test.exs` - extend existing coverage for 64x22, 80x24, and wide terminal sizes.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| SSH terminal feel across an actual client | CHROME-01, CHROME-02, CHROME-03, CHROME-05 | ExUnit verifies render contracts, but terminal emulator font and client behavior may affect perception. | Run the app over SSH at 64x22, 80x24, and a wide terminal; visit Login, Boards, Board, Thread Reader, Account, and Sysop Users; confirm breadcrumb/status/command chrome remains inside the frame without overlap. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 180s for narrow checks
- [ ] `nyquist_compliant: true` set in frontmatter after plan tasks map to concrete tests

**Approval:** pending
