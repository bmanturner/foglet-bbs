# Phase 10: user-status-administration - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md - this log preserves the analysis.

**Date:** 2026-04-24
**Phase:** 10-user-status-administration
**Mode:** assumptions
**Areas analyzed:** Status Persistence, Accounts Transition Boundary, Sysop USERS Surface, Login/Registration/Tasks/Notifications

## Assumptions Presented

### Status Persistence

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| `:rejected` should be added to the existing string-backed `users.status` field, `Ecto.Enum`, and DB check constraint, not converted to a Postgres enum or represented by deletion. | Confident | `docs/DATA_MODEL.md`; `lib/foglet_bbs/accounts/user.ex`; `priv/repo/migrations/20260418010000_add_status_to_users.exs`; `lib/foglet_bbs/accounts.ex` |

### Accounts Transition Boundary

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Phase 10 status changes should be public `Foglet.Accounts` APIs that take an actor and target user, authorize with `Bodyguard.permit/4`, enforce only `pending -> active`, `pending -> rejected`, `active -> suspended`, and `suspended -> active`, and reject deleted users before side effects. | Confident | `lib/foglet_bbs/accounts.ex`; `lib/foglet_bbs/authorization.ex`; `.planning/phases/10-user-status-administration/10-SPEC.md` |

### Sysop USERS Surface

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| The Sysop `USERS` tab should become a screen-local submodule/state surface, following existing `SiteForm`, `LimitsForm`, `BoardsView`, and `SystemSnapshot` delegation patterns, rather than adding direct Repo or Accounts calls inside `Sysop.render/1`. | Likely | `lib/foglet_bbs/tui/screens/sysop.ex`; `lib/foglet_bbs/tui/screens/sysop/state.ex`; `test/foglet_bbs/tui/screens/sysop_test.exs` |

### Login, Registration, Tasks, And Notifications

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Login and registration copy must branch on delivery-mode/status result data from Accounts/Config, while the break-glass task should mirror existing `mix foglet.user.*` command style and print explicit success/failure without claiming email in no-email mode. Prefer one status task with `HANDLE --status active\|rejected\|suspended` over separate verb tasks. | Likely | `lib/foglet_bbs/tui/screens/login.ex`; `lib/foglet_bbs/tui/screens/register.ex`; `lib/mix/tasks/foglet.user.create.ex`; `lib/mix/tasks/foglet.user.promote.ex`; `lib/mix/tasks/foglet.user.reset_password.ex`; `lib/foglet_bbs/accounts.ex` |

## Corrections Made

None. User replied `proceed`, confirming all presented assumptions.

## External Research

Potential research note: Swoosh/Phoenix mailer API and test-adapter details may need official-doc verification if Phase 9 has not landed the delivery-mode implementation before Phase 10 planning.

## Result

Wrote `.planning/phases/10-user-status-administration/10-CONTEXT.md` with confirmed decisions for downstream research and planning.
