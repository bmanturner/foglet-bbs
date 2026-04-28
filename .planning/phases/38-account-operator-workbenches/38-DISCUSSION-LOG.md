# Phase 38: Account & Operator Workbenches - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution
> agents. Decisions captured in CONTEXT.md are the source of truth; this log
> preserves the analysis.

**Date:** 2026-04-28
**Phase:** 38-account-operator-workbenches
**Mode:** assumptions
**Areas analyzed:** Account Ownership, Moderation Ownership, Sysop Ownership, App Boundary and Tests

## Assumptions Presented

### Account Ownership

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Keep the existing Account state/form/SSH/invite shapes, add `init/update/render`, and move saves plus SSH/invite domain actions into Account-owned task effects/results. | Confident | `38-SPEC.md`; `lib/foglet_bbs/tui/screens/account.ex`; `lib/foglet_bbs/tui/screens/account/state.ex`; `lib/foglet_bbs/tui/screens/account/ssh_keys_actions.ex`; `lib/foglet_bbs/tui/screens/shared/invites_actions.ex`; App `account_save_*` clauses |

### Moderation Ownership

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Keep Moderation read-only tables and workspace snapshot shape, but make workspace load and moderator invite domain actions screen-owned task effects/results. LOG/USERS/BOARDS stay navigation-only. | Confident | `38-SPEC.md`; `lib/foglet_bbs/tui/screens/moderation.ex`; `lib/foglet_bbs/tui/screens/moderation/state.ex`; App `load_moderation_workspace` and `moderation_workspace_loaded` clauses |

### Sysop Ownership

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Keep Sysop lifecycle slots and nested submodules, but move lifecycle loading/retry slot transitions and results into `Sysop.update/3`. SITE may stay synchronous only where it is local/read behavior; durable work must stay context-owned and effect-routed. | Likely | `38-SPEC.md`; `lib/foglet_bbs/tui/screens/sysop.ex`; `lib/foglet_bbs/tui/screens/sysop/state.ex`; `lib/foglet_bbs/tui/screens/sysop/limits_form.ex`; App `load_sysop_*`, `sysop_*_loaded`, and `put_sysop_*` helpers |

### App Boundary and Tests

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Use existing generic App helpers, `Effect.task/3`, `route_screen_update/3`, and `{:screen_task_result, screen_key, op, result}`. Tests should assert reducer state/effects and absence of workbench-specific App clauses, not incidental rendered text. | Confident | `lib/foglet_bbs/tui/effect.ex`; `lib/foglet_bbs/tui/context.ex`; `lib/foglet_bbs/tui/app.ex`; prior Phase 34-37 context files; current Account/Moderation/Sysop tests |

## Corrections Made

No corrections - all assumptions confirmed.
