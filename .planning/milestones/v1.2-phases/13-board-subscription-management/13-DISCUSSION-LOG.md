# Phase 13: Board Subscription Management - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md - this log preserves the analysis.

**Date:** 2026-04-24
**Phase:** 13-board-subscription-management
**Mode:** assumptions
**Areas analyzed:** Domain Subscription Boundary, User Terminal Flow, Unsubscribe Safety Rule, Sysop Adjustment Surface

## Assumptions Presented

### Domain Subscription Boundary

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Board subscription management should live in `Foglet.Boards` as public context APIs, extending existing subscription APIs. | Confident | `lib/foglet_bbs/boards.ex`, `lib/foglet_bbs/boards/subscription.ex`, `docs/DATA_MODEL.md`, prior Phase 10/12 context |

### User Terminal Flow

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| The user-facing workflow should be a terminal board directory or management mode in the existing board-list/new-thread area, not a browser/Phoenix workflow. | Confident | `.planning/ROADMAP.md`, `13-SPEC.md`, `lib/foglet_bbs/tui/screens/board_list.ex`, `lib/foglet_bbs/tui/screens/new_thread.ex`, `lib/foglet_bbs/tui/app.ex` |

### Unsubscribe Safety Rule

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Unsubscribe should delete the subscription row only if the user would still have at least one active subscribed board. | Likely | Roadmap wording about not breaking required access assumptions; existing board-list/new-thread flows load subscribed boards only |

### Sysop Adjustment Surface

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Sysop adjustment should use shared `Foglet.Boards` APIs and may use either Sysop `USERS` or a break-glass Mix task, with Mix task as lowest-risk baseline in this checkout. | Likely | `lib/foglet_bbs/tui/screens/sysop.ex`, `lib/foglet_bbs/tui/screens/sysop/state.ex`, `.planning/phases/10-user-status-administration/10-CONTEXT.md`, `lib/mix/tasks/foglet.user.*` |

## Corrections Made

### Specification Check
- **Original issue:** The initial assumption presentation did not load `.planning/phases/13-board-subscription-management/13-SPEC.md`.
- **Correction:** The SPEC exists and locks six requirements. It is now the canonical reference for Phase 13 context.
- **Impact:** The context captures implementation decisions under the SPEC rather than inferring from roadmap alone.

### Unsubscribe Safety Rule
- **Original assumption:** Unsubscribe should be blocked when it would leave the user with zero active board subscriptions.
- **User correction:** Foglet should support users who do not want to be subscribed to any boards.
- **Final decision:** Users may unsubscribe down to zero board subscriptions. The only board-level unsubscribe blocker is the persisted required-subscription policy.

### Required Subscription Policy
- **Original assumption:** The phase might use an access-assumption rule based on remaining subscriptions.
- **User correction:** A new column is required to dictate inability to unsubscribe.
- **Final decision:** Add a persisted board-level required-subscription column, valid only with `default_subscription: true`, and enforce it through schema/context/TUI/task behavior.

### Sysop Adjustment Surface
- **Original assumption:** Sysop adjustment could be through Sysop `USERS` if Phase 10 lands it, or through a Mix task.
- **User correction:** The only sysop-related functionality for this phase is the Mix task.
- **Final decision:** Phase 13 operator subscription adjustment is the break-glass Mix task path. Full Sysop `USERS` terminal subscription management is out of scope.

## External Research

No external research was performed; the SPEC and codebase provided enough evidence.
