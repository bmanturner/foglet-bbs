---
phase: 16
slug: unicode-width-foundation
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-04-25
---

# Phase 16 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit via Elixir 1.19.5 |
| **Config file** | `test/test_helper.exs` |
| **Quick run command** | `rtk mix test test/foglet_bbs/tui/text_width_test.exs test/foglet_bbs/tui/widgets/list/list_row_test.exs test/foglet_bbs/tui/widgets/modal_test.exs test/foglet_bbs/tui/widgets/compose_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` |
| **Full suite command** | `rtk mix test` |
| **Estimated runtime** | ~60 seconds for focused TUI tests; full suite depends on local database state |

---

## Sampling Rate

- **After every task commit:** Run the focused test file for the touched helper or widget.
- **After every plan wave:** Run `rtk mix test test/foglet_bbs/tui/text_width_test.exs test/foglet_bbs/tui/widgets/list/list_row_test.exs test/foglet_bbs/tui/widgets/modal_test.exs test/foglet_bbs/tui/widgets/compose_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`.
- **Before `$gsd-verify-work`:** Run `rtk mix precommit`.
- **Max feedback latency:** 60 seconds for focused feedback.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 16-01-01 | 01 | 1 | WIDTH-01, WIDTH-03 | T-16-01 | N/A - pure TUI layout helper | unit | `rtk mix test test/foglet_bbs/tui/text_width_test.exs` | no - W0 | pending |
| 16-02-01 | 02 | 1 | WIDTH-02, WIDTH-04 | T-16-02 | N/A - no domain mutation | unit | `rtk mix test test/foglet_bbs/tui/widgets/list/list_row_test.exs` | yes | pending |
| 16-03-01 | 03 | 1 | WIDTH-02, WIDTH-05 | T-16-03 | N/A - no authorization change | unit/smoke | `rtk mix test test/foglet_bbs/tui/widgets/chrome/key_bar_test.exs test/foglet_bbs/tui/widgets/modal_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` | partial - W0 for key bar | pending |
| 16-04-01 | 04 | 2 | WIDTH-02, WIDTH-04 | T-16-04 | Character-count validation remains unchanged | unit | `rtk mix test test/foglet_bbs/tui/widgets/compose_test.exs` | yes | pending |
| 16-05-01 | 05 | 2 | WIDTH-02, WIDTH-05 | T-16-05 | Remaining direct string operations documented as display-safe or character-count policy | static/unit | `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` | yes | pending |

*Status: pending, green, red, or flaky.*

---

## Wave 0 Requirements

- [ ] `test/foglet_bbs/tui/text_width_test.exs` - stubs for WIDTH-01 and WIDTH-03.
- [ ] `test/foglet_bbs/tui/widgets/chrome/key_bar_test.exs` - command-footer display-width behavior.
- [ ] `test/foglet_bbs/tui/layout_smoke_test.exs` - dimension parameterization for 64x22, 80x24, and wide/tall.
- [ ] Existing row, modal, and compose tests include Unicode display-width assertions.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Real terminal font rendering for ambiguous Unicode and emoji | WIDTH-03 | Phase 16 locks to Raxol's model and the SCREENS.md glyph set; terminal/font variance is out of scope. | Optional SSH smoke check after automated tests pass. Do not block Phase 16 on ambiguous emoji width. |

---

## Validation Sign-Off

- [x] All planned task areas have automated verification or Wave 0 dependencies.
- [x] Sampling continuity: no 3 consecutive tasks without automated verification.
- [x] Wave 0 covers all missing test-file references.
- [x] No watch-mode flags.
- [x] Feedback latency target is below 60 seconds for focused tests.
- [x] `nyquist_compliant: true` set in frontmatter.

**Approval:** approved 2026-04-25 for planning
