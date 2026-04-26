---
phase: 20
slug: rich-rows-and-thread-flow
status: phase20_validated_with_external_precommit_blocker
nyquist_compliant: true
wave_0_complete: true
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
| 20-01.T1 | 01 | 0 | RICHROW-01 / THREADS-02 | T-20-01..06 | N/A (pure render) | unit | `rtk mix test test/foglet_bbs/tui/widgets/list/rich_row_test.exs` | ✅ | ✅ green |
| 20-02.T1 | 02 | 0 | THREADS-01 | T-20-07..12 | N/A | unit | `rtk mix test test/foglet_bbs/tui/screens/thread_list_test.exs` | ✅ | ✅ green |
| 20-03.T1 | 03 | 0 | RICHROW-01 / THREADS-01 | T-20-13..18 | N/A | smoke | `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` | ✅ | ✅ green |
| 20-04.T1 | 04 | 1 | RICHROW-01 / THREADS-02 | T-20-19..24 | N/A | unit | `rtk mix test test/foglet_bbs/tui/widgets/list/rich_row_test.exs` | ✅ | ✅ green |
| 20-05.T1 | 05 | 2 | THREADS-01 / THREADS-02 | T-20-25..30 | N/A | unit + smoke | `rtk mix test test/foglet_bbs/tui/screens/thread_list_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` | ✅ | ✅ green |
| 20-06.T2 | 06 | 3 | RICHROW-01 / THREADS-01 / THREADS-02 | All | N/A | full | `rtk mix precommit` | ✅ | ⚠️ blocked by unrelated `main_menu.ex` Credo findings |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

> **Note:** This table is populated by Plan 20-06 Task 3 once Wave 0/1/2 complete. Each row maps a task ID to a requirement, an automated command, and Wave 0 readiness.

## Precommit Gate Status

`rtk mix precommit` was run end-to-end during Plan 20-06. Phase 20-related
Credo findings were fixed in `test/foglet_bbs/tui/screens/thread_list_test.exs`
and `test/foglet_bbs/tui/layout_smoke_test.exs`, and the focused Phase 20 TUI
suite passes:

```text
rtk mix test test/foglet_bbs/tui/widgets/list/rich_row_test.exs test/foglet_bbs/tui/screens/thread_list_test.exs test/foglet_bbs/tui/layout_smoke_test.exs
75 tests, 0 failures
```

The full project precommit remains blocked by unrelated, pre-existing Credo
refactoring findings outside Phase 20 ownership:

```text
lib/foglet_bbs/tui/screens/main_menu.ex:223
One Enum.filter/2 is more efficient than Enum.filter/2 |> Enum.filter/2

lib/foglet_bbs/tui/screens/main_menu.ex:245
One Enum.filter/2 is more efficient than Enum.filter/2 |> Enum.filter/2
```

Per the Plan 20-06 execution instruction, these findings are documented here
instead of broadening scope into non-Phase-20 code.

Additional broad TUI validation was also attempted with
`rtk mix test test/foglet_bbs/tui/`. The Phase 20 owned files are green, but the
full directory run currently reports 1034 tests with 3 failures in
`test/foglet_bbs/tui/app_test.exs` through the login/config DB ownership path.
That file and failure path are outside Phase 20 RichRow/ThreadList ownership
and are recorded here rather than widened into this plan.

---

## THREADS-02 Reinterpretation (Accepted Product Decision)

**Roadmap wording:** "focused-thread details appear without disrupting
keyboard navigation."

**Phase 20 interpretation:** THREADS-02 is satisfied via SELECTION CLARITY
(selection clarity)
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

- [x] `test/foglet_bbs/tui/widgets/list/rich_row_test.exs` — new widget unit test file covering RICHROW-01 (render matrix, theme hygiene, cluster-width property invariant, selection-vs-state-glyph precedence, optional metadata) and THREADS-02 (focused-row uniqueness)
- [x] Extend `test/foglet_bbs/tui/screens/thread_list_test.exs` LIST-03 describe block (~line 221) — glyph presence per state, `[S]` absence, row-isolated cluster-width invariance (THREADS-01)
- [x] Extend `test/foglet_bbs/tui/layout_smoke_test.exs` — new `thread_list — size contract` describe block at `[{64,22}, {80,24}, {132,50}]` with row-isolation helper (RICHROW-01 / THREADS-01)
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

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter
- [x] THREADS-02 Reinterpretation section present and explicit

**Approval:** approved 2026-04-25 (Phase 20 scoped; full project precommit has the unrelated `main_menu.ex` blocker documented above)
