---
phase: 19
slug: main-menu-dashboard
status: planned
nyquist_compliant: true
wave_0_complete: false
created: 2026-04-25
updated: 2026-04-25
---

# Phase 19 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (Elixir built-in) |
| **Config file** | `mix.exs` (no separate test config) |
| **Quick run command** | `rtk mix test test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` |
| **Full suite command** | `rtk mix precommit` (compile w/ warnings-as-errors, format, Credo, Sobelow, Dialyzer, full test) |
| **Estimated runtime** | Quick: ~3-5s · Full precommit: ~60-120s |

---

## Sampling Rate

- **After every task commit:** Run `rtk mix test test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`
- **After every plan wave:** Run `rtk mix test test/foglet_bbs/tui/`
- **Before `/gsd-verify-work`:** `rtk mix precommit` must be green
- **Max feedback latency:** ~5s for quick, ~120s for full precommit

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 19-01-01 | 01 | 1 | HOME-01 | T-19-01, T-19-02, T-19-03 | Role gating via ShellVisibility + Bodyguard.permit?; B/C/A/M/S/Q never appear in command bar | unit | `rtk mix test test/foglet_bbs/tui/screens/main_menu_test.exs` | ✅ extends existing | ⬜ pending |
| 19-02-01 | 02 | 2 | HOME-02, HOME-01 | T-19-05, T-19-06, T-19-07 | TextWidth-based right-align math; theme-routed styling (no hardcoded color atoms); oneliner clipping via slice_to_width | unit | `rtk mix test test/foglet_bbs/tui/screens/main_menu_test.exs` | ✅ extends existing | ⬜ pending |
| 19-03-01 | 03 | 3 | HOME-03 | T-19-08, T-19-09, T-19-10 | Side-by-side at 64x22/80x24/132x50; viewport-bound + no-overlap assertions; D-17 forbids new test file | smoke | `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` | ✅ extends existing | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Phase 19 has NO net-new test files (D-15, D-16, D-17 forbid them). All Wave 0 gaps from RESEARCH.md §Validation Architecture are addressed in-place inside Plan 01, Plan 02, and Plan 03 task `<action>` blocks:

- [x] (Plan 01) `test/foglet_bbs/tui/screens/main_menu_test.exs` — new "Phase 19 destinations vs. actions split" describe block including the "command bar non-duplication" invariant test (B/C/A/M/S/Q never appear in command-bar groups).
- [x] (Plan 02) `test/foglet_bbs/tui/screens/main_menu_test.exs` — `"render includes main menu owned text rows"` test rewritten: removes `"Welcome back, alice."` assertion; adds `"Navigation"` panel header assertion; adds glyph-row regex assertions (`/●\s+Boards\s+B$/` etc.).
- [x] (Plan 02) `test/foglet_bbs/tui/screens/main_menu_test.exs` — new "Phase 19 body visual" describe block with per-row width-budget compliance test.
- [x] (Plan 03) `test/foglet_bbs/tui/layout_smoke_test.exs` — Main Menu block at lines 318-351 rewritten: removes `"Welcome"` assertion; adds `"Navigation"` panel header assertion; adapts `[B]`/`[Q]` literal-bracket assertions to glyph-row regex shape.
- [x] (Plan 03) `test/foglet_bbs/tui/layout_smoke_test.exs` — new "Phase 19 Main Menu size contracts" describe block iterating `[{64,22},{80,24},{132,50}]` with viewport-bound, side-by-side, and no-overlap assertions.

NO new test file may be created. Acceptance criteria in Plan 03 explicitly assert absence of `test/foglet_bbs/tui/screens/main_menu_layout_test.exs` and `test/foglet_bbs/tui/main_menu_layout_test.exs` (D-17).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Glyph cell-width on real SSH terminals | HOME-02 | RESEARCH.md Pitfall 5: some East Asian font configurations treat ambiguous-width glyphs (`●`, `◇`, `▣`) as 2 cells while EAW classifies them as Neutral (1 cell). Positioned-render tests use the layout engine's measurement, not real terminal rendering. | After execution, SSH into the local dev server with three terminals: macOS Terminal.app default, iTerm2 with a CJK-friendly font (e.g. Source Han Sans), and a tmux/byobu session. Resize each to 64x22, 80x24, 132x50. Verify Navigation panel rows render flush (key letter at right margin) and no glyph wraps. If a row breaks alignment in a specific font, document the font + terminal combination and consider invoking D-10 ASCII fallback in a follow-up phase. |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify commands in their `<verify>` blocks
- [x] Sampling continuity: every task has a single-command quick-run that exits 0; no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references — handled in-place per D-15/D-16/D-17 (no new files)
- [x] No watch-mode flags
- [x] Feedback latency < 5s for quick run; < 120s for precommit
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-04-25 (planner sign-off; awaiting execution)
