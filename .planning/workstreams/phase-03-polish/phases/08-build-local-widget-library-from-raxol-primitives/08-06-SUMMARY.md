---
phase: "08"
plan: "06"
subsystem: tui/chrome
tags: [raxol, audit, layout, spacer, justify_content, chrome, refactor]
dependency_graph:
  requires: []
  provides: [REQ-W-14]
  affects: [lib/foglet_bbs/tui/size_gate.ex, lib/foglet_bbs/tui/widgets/chrome/status_bar.ex, lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex]
tech_stack:
  added: []
  patterns: [audit-comments, justify-vs-spacer decision record]
key_files:
  created: []
  modified:
    - lib/foglet_bbs/tui/size_gate.ex
    - lib/foglet_bbs/tui/widgets/chrome/status_bar.ex
    - lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex
decisions:
  - "All three justify_* call sites kept — spacer/1 is fixed-size and cannot reproduce flex-grow behavior without caller-computed sizes"
metrics:
  duration: "~15 minutes"
  completed: "2026-04-20"
---

# Phase 8 Plan 06 — `spacer()` Adoption Audit — Summary

**Plan:** 08-06-PLAN.md (ROADMAP Phase 8 goal, clause 2)
**Requirement closed:** REQ-W-14
**Date:** 2026-04-20
**Scope:** Audit every `justify_*` call site in `lib/` and decide per-site whether `spacer()` reads more naturally.

**One-liner:** Documented the spacer/1 fixed-size finding in all three chrome/size-gate files, closing REQ-W-14 without any behavior change.

## Audit result

| Site | File | Disposition | Rationale |
|------|------|-------------|-----------|
| A | `lib/foglet_bbs/tui/size_gate.ex:80` | KEEP `justify_content: :center, align_items: :center` | `spacer/1` has fixed size (`vendor/raxol/lib/raxol/view/components.ex:164-172`); cannot reproduce `:center` without caller-computed sizes — strictly less readable. |
| B | `lib/foglet_bbs/tui/widgets/chrome/status_bar.ex:44` | KEEP `justify_content: :space_between` | `spacer/1` does not flex-grow; reproducing `:space_between` would require dynamic width measurement of `text` children at call time. |
| C | `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex:37` | KEEP `justify_content: :space_between` | Same as B, on the vertical axis — plus `content_element` is an opaque Raxol element (D-05 lock); parent cannot measure its height. |

## Net change

- 3 files touched (comments only).
- 0 `justify_*` sites refactored.
- 0 `spacer()` calls added in `lib/`.
- 0 test files changed.
- 0 behavior changes in chrome or SizeGate rendering.

## Why the audit still closed the requirement

The ROADMAP goal clause 2 reads *"adopt where they read more naturally"*. Reading the Raxol `spacer/1` source shows it cannot replace `justify_*` without a readability regression (introducing caller-computed sizes). Documenting this decision in the three files prevents a future maintainer from re-litigating it; that is the deliverable.

## Precommit

`mix compile --warnings-as-errors` — green for foglet_bbs (raxol vendor warnings are pre-existing and unrelated).
`mix format --check-formatted` — green for all three modified files.
`mix test` (targeted: size_gate, app_test, layout_smoke_test, main_menu_test) — 124 tests, 0 failures.

`mix credo --strict` — pre-existing violations in out-of-scope files caused the full `mix precommit` gate to exit non-zero. The violations are in `lib/foglet_bbs/tui/screens/post_composer.ex` (cyclomatic complexity, pre-existing), `lib/foglet_bbs/tui/screens/login.ex` (cyclomatic complexity, pre-existing), and alias ordering in two test files. None are caused by this plan. Confirmed pre-existing by running credo against the base commit before any changes.

## Deviations from Plan

### Out-of-scope pre-existing issues (deferred)

**Pre-existing credo failures** (not caused by this plan):
- `lib/foglet_bbs/tui/screens/post_composer.ex:271` — cyclomatic complexity 10, max 9 (`do_submit`)
- `lib/foglet_bbs/tui/screens/login.ex:263` — cyclomatic complexity 11, max 9 (`submit_login`)
- `test/foglet_bbs/tui/screens/thread_list_test.exs:124` — alias ordering (`FakeThreads`)
- `test/foglet_bbs/tui/screens/new_thread_test.exs:45` — alias ordering (`FakeThreadsOk`)

These existed before the plan started (verified by stash check) and are outside this plan's scope. Logged for the next credo cleanup pass.

## Follow-up

If a future plan introduces a chrome layout where `content_element`'s height is known at build time (e.g., a fully statically-sized screen), revisit Site C. Otherwise this audit is durable.

If `mix credo --strict` pre-existing failures should be fixed before the next wave, a dedicated cleanup plan is needed for the four out-of-scope violations above.

## Self-Check: PASSED

- `lib/foglet_bbs/tui/size_gate.ex` — FOUND, contains `08-06 audit` comment
- `lib/foglet_bbs/tui/widgets/chrome/status_bar.ex` — FOUND, contains `08-06 audit` comment
- `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` — FOUND, contains `08-06 audit` comment
- Task 1 commit `820cf8f` — FOUND
