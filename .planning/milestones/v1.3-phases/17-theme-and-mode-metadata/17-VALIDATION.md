---
phase: 17
slug: theme-and-mode-metadata
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-04-25
---

# Phase 17 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit bundled with Elixir 1.19.5 |
| **Config file** | `test/test_helper.exs` |
| **Quick run command** | `rtk mix test test/foglet_bbs/tui/theme_test.exs test/foglet_bbs/tui/presentation_test.exs test/foglet_bbs/tui/widgets/input/tabs_test.exs test/foglet_bbs/tui/widgets/input/radio_group_test.exs test/foglet_bbs/tui/widgets/input/checkbox_test.exs test/foglet_bbs/tui/widgets/modal_test.exs` |
| **Full suite command** | `rtk mix test` |
| **Estimated runtime** | ~10 seconds for focused tests; full suite runtime varies |

---

## Sampling Rate

- **After every task commit:** Run the focused test command for the touched widget group plus `rtk mix test test/foglet_bbs/tui/theme_test.exs test/foglet_bbs/tui/presentation_test.exs`
- **After every plan wave:** Run `rtk mix test`
- **Before `$gsd-verify-work`:** `rtk mix precommit` must pass
- **Max feedback latency:** 10 seconds for focused tests

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 17-01-01 | 01 | 1 | MODE-01 | T-17-01 | Unknown screen ids do not silently default to a valid presentation mode | unit | `rtk mix test test/foglet_bbs/tui/presentation_test.exs` | No - W0 | pending |
| 17-01-02 | 01 | 1 | THEME-02 | T-17-02 | Presentation mode remains presentation metadata, not authorization | unit | `rtk mix test test/foglet_bbs/tui/presentation_test.exs` | No - W0 | pending |
| 17-02-01 | 02 | 1 | THEME-01 | - | Every palette resolves non-empty semantic slots through `Foglet.TUI.Theme` | unit | `rtk mix test test/foglet_bbs/tui/theme_test.exs` | Yes, needs expansion | pending |
| 17-03-01 | 03 | 1 | THEME-02 | - | Mapping contract references only valid `Foglet.TUI.Theme` slots | unit | `rtk mix test test/foglet_bbs/tui/presentation_test.exs` | No - W0 | pending |
| 17-04-01 | 04 | 3 | THEME-01 / THEME-02 | T-17-10 | Catalog-only primitives use theme slots instead of hardcoded colors | unit | `rtk mix test test/foglet_bbs/tui/widgets/input/button_test.exs test/foglet_bbs/tui/widgets/input/menu_test.exs test/foglet_bbs/tui/widgets/list/smart_list_test.exs test/foglet_bbs/tui/widgets/display/progress_test.exs` | Yes, needs expansion | pending |
| 17-04-02 | 04 | 3 | THEME-01 / THEME-02 | T-17-10 | Used input primitives visibly honor theme slot mappings | unit | `rtk mix test test/foglet_bbs/tui/widgets/input/tabs_test.exs test/foglet_bbs/tui/widgets/input/radio_group_test.exs test/foglet_bbs/tui/widgets/input/checkbox_test.exs` | Yes, needs expansion | pending |
| 17-04-03 | 04 | 3 | THEME-01 / THEME-02 | T-17-10 / T-17-12 | Selection, loading, and generic modal states remain presentational and theme-routed | unit | `rtk mix test test/foglet_bbs/tui/widgets/list/selection_list_test.exs test/foglet_bbs/tui/widgets/progress/spinner_test.exs test/foglet_bbs/tui/widgets/modal_test.exs` | Yes, needs expansion | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [ ] `test/foglet_bbs/tui/presentation_test.exs` - stubs for MODE-01 and THEME-02.
- [ ] `test/foglet_bbs/tui/theme_test.exs` - extend existing tests for THEME-01.
- [ ] Optional public `Foglet.TUI.Theme.slot_keys/0` - needed if mapping validation should avoid duplicating private `@slot_keys`.
- [ ] Existing widget tests for Button, Menu, SmartList, Display.Progress, Tabs, RadioGroup, Checkbox, SelectionList, Spinner, and generic Modal - extend for semantic theme routing.

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Security Notes

| Threat Ref | Behavior | Standard Mitigation | Verification |
|------------|----------|---------------------|--------------|
| T-17-01 | Unknown screen id silently defaults to `:bbs` or `:operator` | Raise or return an explicit error for unknown ids | `presentation_test.exs` asserts unknown id behavior |
| T-17-02 | Presentation mode gets treated as authorization | Keep authorization in `Foglet.Authorization`; mode metadata is display-only | Plan threat model must state that mode is not a permission boundary |

---

## Validation Sign-Off

- [x] All tasks have automated verify commands or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all missing references
- [x] No watch-mode flags
- [x] Feedback latency < 10s for focused tests
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-04-25
