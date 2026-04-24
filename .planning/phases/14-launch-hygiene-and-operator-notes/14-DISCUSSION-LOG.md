# Phase 14: Launch Hygiene and Operator Notes - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md - this log preserves the analysis.

**Date:** 2026-04-24
**Phase:** 14-launch-hygiene-and-operator-notes
**Mode:** assumptions
**Areas analyzed:** Phase Boundary, Sysop Config Accountability, Launch-Facing Copy And README, Test Audit Shape

## Assumptions Presented

### Phase Boundary

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Phase 14 should audit and polish final behavior from Phases 9-13, but any major missing Phase 9-13 capability should be reported as an upstream blocker rather than implemented inside Phase 14. | Confident | `.planning/phases/14-launch-hygiene-and-operator-notes/14-SPEC.md`, `lib/foglet_bbs/tui/screens/sysop.ex`, `lib/foglet_bbs/accounts/user.ex`, `lib/foglet_bbs/boards.ex`, `lib/foglet_bbs/threads.ex`, `lib/foglet_bbs/posts.ex` |

### Sysop Config Accountability

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Config accountability should be driven by `Foglet.Config.Schema.entries/0` compared against Sysop form key lists, with keys classified as visible, conditionally visible, intentionally hidden, or non-pre-alpha. | Confident | `lib/foglet_bbs/config/schema.ex`, `lib/foglet_bbs/tui/screens/sysop/site_form.ex`, `lib/foglet_bbs/tui/screens/sysop/limits_form.ex`, `test/foglet_bbs/tui/screens/sysop_test.exs` |

### Launch-Facing Copy And README

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Phase 14 should include a cross-surface copy audit over TUI screens, Mix tasks, and root `README.md`, prioritizing removal of false email/browser/sysop-action claims. | Confident | `.planning/phases/14-launch-hygiene-and-operator-notes/14-SPEC.md`, `lib/foglet_bbs/tui/screens/verify.ex`, `lib/foglet_bbs/tui/screens/register.ex`, `lib/mix/tasks/foglet.user.reset_password.ex`, `README.md` |

### Test Audit Shape

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| The test audit should preserve behavior-rich context/TUI/Mix tests, add focused coverage for visible launch claims, and prune only tests that are static or redundant. | Likely | `.planning/phases/14-launch-hygiene-and-operator-notes/14-SPEC.md`, `test/foglet_bbs/config_test.exs`, `test/foglet_bbs/config/schema_test.exs`, `test/foglet_bbs/tui/screens/sysop_test.exs`, `test/foglet_bbs/tui/screens/login_test.exs`, `test/foglet_bbs/tui/screens/verify_test.exs` |

## Corrections Made

No corrections - all assumptions confirmed.
