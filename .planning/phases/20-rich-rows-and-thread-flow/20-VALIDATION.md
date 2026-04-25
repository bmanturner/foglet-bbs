---
phase: 20
slug: rich-rows-and-thread-flow
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-25
revised: 2026-04-25
---

# Phase 20 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (Elixir standard) |
| **Config file** | `test/test_helper.exs` |
| **Quick run command** | `rtk mix test test/foglet_bbs/tui/widgets/list/rich_row_test.exs` |
| **Full suite command** | `rtk mix test test/foglet_bbs/tui/` |
| **Estimated runtime** | ~30 seconds (full TUI suite) |

---

## Sampling Rate

- **After every task commit:** Run `rtk mix test test/foglet_bbs/tui/widgets/list/rich_row_test.exs` (or screen test for ThreadList tasks)
- **After every plan wave:** Run `rtk mix test test/foglet_bbs/tui/`
- **Before `/gsd-verify-work`:** `rtk mix precommit` (the project-defined alias from `mix.exs`) must be green
- **Max feedback latency:** ~30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| Filled by Plan 20-06 Task 3 | — | — | RICHROW-01 / THREADS-01 / THREADS-02 | — | N/A (pure render) | unit / smoke | per-plan | per-plan | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

> **Note:** This table is populated by Plan 20-06 Task 3 once Wave 0/1/2 complete. Each row maps a task ID to a requirement, an automated command, and Wave 0 readiness.

---

## THREADS-02 Reinterpretation (Accepted Product Decision)

**Roadmap wording:** "focused-thread details appear without disrupting
keyboard navigation."

**Phase 20 interpretation:** THREADS-02 is satisfied via SELECTION CLARITY
— each row in the thread list highlights distinctly when it is the
currently focused row (per `theme.selected.bg` + `:bold` + `▌ ` focus
marker). There is no separate focused-thread details strip in scope for
Phase 20.

**Status:** Accepted product decision. Recorded here so future planners
do not treat THREADS-02 as an unmet requirement requiring a details strip.

**Verification:** Plan 20-01 Tests 9-10 (focused-row uniqueness assertions)
prove that focused rows have at least one styling property no non-focused
row shares. Plan 20-04 implements that uniqueness via the
selection-vs-state-glyph styling described in the RichRow `@moduledoc` —
selected rows adopt `theme.selected.bg` while glyph foregrounds keep their
state slot (`accent`/`info`/`warning`).

**Reference:** 20-REVIEWS.md HIGH #3 (codex / gpt-5.5) raised this
divergence; user decision #4 in the planner's reviews-mode invocation
accepted the reinterpretation. Plan 20-06 Task 3 re-asserts this section
when it stamps `nyquist_compliant: true` and `wave_0_complete: true`.

---

## Wave 0 Requirements

- [ ] `test/foglet_bbs/tui/widgets/list/rich_row_test.exs` — new widget unit test file covering RICHROW-01 (render matrix, theme hygiene, cluster-width property invariant, selection-vs-state-glyph precedence, optional metadata) and THREADS-02 (focused-row uniqueness)
- [ ] Extend `test/foglet_bbs/tui/screens/thread_list_test.exs` LIST-03 describe block (~line 221) — glyph presence per state, `[S]` absence, row-isolated cluster-width invariance (THREADS-01)
- [ ] Extend `test/foglet_bbs/tui/layout_smoke_test.exs` — new `thread_list — size contract` describe block at `[{64,22}, {80,24}, {132,50}]` with row-isolation helper (RICHROW-01 / THREADS-01)
- ExUnit and `rtk mix` already installed — no framework install needed.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Visual contrast of `●` (sticky) on terminal background across nine themes | THREADS-01 | Glyph contrast varies with terminal background and palette; not assertable in code | SSH into the local server with each theme set, browse a thread list with sticky/unread/locked rows, verify all three glyphs are visually distinct from row background. |
| `⚿` (locked) renders as a visible glyph (not tofu `□`) on PuTTY/Windows Terminal | THREADS-01 | Cross-terminal font coverage is environmental; layout still holds (D-07 response: swap glyph) | Connect from PuTTY and Windows Terminal SSH client, view a locked thread row, confirm glyph is visible. If tofu, switch glyph to another single-cell symbol per D-07. |
| Selected sticky row visually preserves the sticky-color `●` glyph (not overpainted to selection fg) | THREADS-02 | Selection-vs-state-glyph precedence is verified in code, but actual contrast on a real terminal needs eyeballs across themes | SSH in, focus a sticky row in the thread list, verify the `●` color is recognisably the sticky/info color while the row background is the selection background. Repeat for unread `◆` and locked `⚿`. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter
- [ ] THREADS-02 Reinterpretation section present and explicit

**Approval:** pending
