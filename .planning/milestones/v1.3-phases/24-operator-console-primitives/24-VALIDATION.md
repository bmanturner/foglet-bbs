---
phase: 24
slug: operator-console-primitives
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-25
---

# Phase 24 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit |
| **Config file** | `mix.exs` |
| **Quick run command** | `rtk mix test test/foglet_bbs/tui/widgets/display/badge_test.exs test/foglet_bbs/tui/widgets/display/kv_grid_test.exs test/foglet_bbs/tui/widgets/display/console_table_test.exs test/foglet_bbs/tui/widgets/workspace/inspector_test.exs test/foglet_bbs/tui/widgets/modal/form_test.exs` |
| **Full suite command** | `rtk mix precommit` |
| **Estimated runtime** | Quick: < 15 seconds; full precommit varies with Dialyzer |

---

## Sampling Rate

- **After every task commit:** Run the focused test file named in the plan task.
- **After every plan wave:** Run the quick widget suite.
- **Before `$gsd-verify-work`:** `rtk mix precommit` must be green.
- **Max feedback latency:** One focused ExUnit file per primitive task.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 24-01-01 | 01 | 1 | CONSOLE-01 | T-24-01 | No domain side effects; theme-routed badge styles | unit | `rtk mix test test/foglet_bbs/tui/widgets/display/badge_test.exs` | W0 existing infra | pending |
| 24-02-01 | 02 | 1 | CONSOLE-02 | T-24-02 | Pure caller-provided rows; width-safe truncation | unit | `rtk mix test test/foglet_bbs/tui/widgets/display/kv_grid_test.exs` | W0 existing infra | pending |
| 24-03-01 | 03 | 2 | CONSOLE-03 | T-24-03 | Delegates to Display.Table; no domain calls | unit | `rtk mix test test/foglet_bbs/tui/widgets/display/console_table_test.exs test/foglet_bbs/tui/widgets/display/table_test.exs` | W0 existing infra | pending |
| 24-04-01 | 04 | 2 | CONSOLE-03 | T-24-04 | Inspector renders caller-provided actions only | unit | `rtk mix test test/foglet_bbs/tui/widgets/workspace/inspector_test.exs` | W0 existing infra | pending |
| 24-05-01 | 05 | 3 | CONSOLE-04 | T-24-05 | Preserves Modal.Form event semantics and body-only overlay | unit | `rtk mix test test/foglet_bbs/tui/widgets/modal/form_test.exs` | W0 existing infra | pending |
| 24-06-01 | 06 | 3 | CONSOLE-01, CONSOLE-02, CONSOLE-03, CONSOLE-04 | T-24-06 | Catalog/docs reflect primitive boundaries without runtime behavior changes | regression | `rtk mix test test/foglet_bbs/tui/widgets/catalog_smoke_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` | W0 existing infra | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements:

- `ExUnit` is already configured.
- `test/support/foglet/tui/widget_helpers.ex` already provides `flatten_text/1`,
  `color_atom_leaked?/2`, `color_names/0`, and style-run helpers.
- `Foglet.TUI.TextWidth` already provides width-safe display measurement,
  truncation, and padding helpers.

---

## Manual-Only Verifications

All phase behaviors have automated verification. Phase 24 does not require a
manual SSH smoke test because it creates primitive widgets and fixture coverage
only; Phase 25 should add screen-level SSH/TUI validation when adopting them.

---

## Validation Sign-Off

- [x] All tasks have automated verify commands or existing Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all missing test infrastructure references
- [x] No watch-mode flags
- [x] Feedback latency is bounded by focused ExUnit files
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-04-25
