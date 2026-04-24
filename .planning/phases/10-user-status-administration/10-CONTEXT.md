# Phase 10: user-status-administration - Context

**Gathered:** 2026-04-24 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Sysops can approve, reject, suspend, and reactivate users through actor-aware terminal and break-glass workflows. This phase adds durable `:rejected` account status, the locked status-transition graph, Sysop `USERS` administration, one operator status task, SMTP-mode pending-user approval notifications, and accurate login outcomes/copy for pending, rejected, suspended, active, and reactivated users. It does not add appeals, arbitrary status editing, bulk actions, search/pagination polish, richer admin histories, board subscription controls, browser administration, or v2 notification infrastructure.
</domain>

<decisions>
## Implementation Decisions

### Status Persistence
- **D-01:** Add `:rejected` to the existing string-backed `users.status` model: `Foglet.Accounts.User` `Ecto.Enum`, schema validation, migration/check constraint, data model docs, fixtures, and focused tests.
- **D-02:** Do not represent rejected registrations as soft deletion, deleted rows, or a separate appeals table. Rejected users remain non-deleted user rows so handles and emails stay reserved and login can report the correct state.
- **D-03:** Do not convert `users.status` to a Postgres enum for this phase; keep the current project pattern of string-backed enum-like fields that can grow through migrations and changeset validation.

### Accounts Transition Boundary
- **D-04:** Status changes are public `Foglet.Accounts` APIs that accept an actor and a target user or target handle/id; TUI and Mix code must call those APIs rather than updating Repo directly.
- **D-05:** Actor-triggered status changes must authorize with `Bodyguard.permit/4` before side effects. Add a sysop-only authorization action or actions rather than relying on menu visibility.
- **D-06:** Enforce exactly the locked transition graph in the context: `pending -> active`, `pending -> rejected`, `active -> suspended`, and `suspended -> active`.
- **D-07:** Invalid transitions, deleted targets, unknown targets, and non-sysop actors fail without changing persisted status or sending notifications.
- **D-08:** Status transition APIs should return tagged results that let TUI, Mix tasks, and tests distinguish success, forbidden, not found/deleted, invalid transition, and delivery-warning cases without parsing text.

### Sysop USERS Surface
- **D-09:** Replace the Sysop `USERS` placeholder with a screen-local submodule/state surface following the existing `SiteForm`, `LimitsForm`, `BoardsView`, and `SystemSnapshot` delegation pattern.
- **D-10:** Keep `Foglet.TUI.Screens.Sysop` as the shell/router for tabs; do not put user-list state, selection state, Repo queries, or transition side effects in `Sysop.render/1`.
- **D-11:** The `USERS` tab should list pending users for approve/reject and enough active/suspended/rejected non-deleted users for status administration. It does not need search, bulk actions, rich history, pagination polish, role changes, or profile editing.
- **D-12:** Valid actions should call the Accounts transition API and surface any forbidden/invalid/deleted/delivery-warning result as terminal copy or a modal; failures must not silently no-op.

### Login, Registration, Tasks, And Notifications
- **D-13:** Login and registration copy must branch from Accounts/Config delivery-mode and status results, not hardcoded assumptions that email was sent.
- **D-14:** Add a rejected-login branch alongside pending and suspended so rejected users receive accurate terminal copy and cannot proceed.
- **D-15:** Approval and rejection notifications are attempted only when SMTP delivery is configured through the Phase 9 delivery-mode contract. No-email mode still completes the status transition but must not claim email delivery.
- **D-16:** Delivery failure should not roll back an otherwise valid status transition unless research/planning deliberately chooses and tests a stricter policy. The default planning assumption is transition succeeds and callers receive an explicit delivery warning.
- **D-17:** Add one break-glass Mix task in the existing `mix foglet.user.*` style. Prefer a single status task accepting a handle and target status (`active`, `rejected`, or `suspended`) over separate verb tasks, while reusing the same Accounts transition validation.
- **D-18:** The break-glass task output must be explicit about whether the status changed and whether any notification was attempted, skipped, or failed.

### the agent's Discretion
- Exact Accounts function names and return tuple shapes, provided they are typed, public, testable, and distinguish the required failure modes.
- Exact authorization action atom names, provided they are sysop-only and use `Bodyguard.permit/4`.
- Exact Sysop `USERS` tab interaction model and key bindings, provided it remains terminal-native and can administer the locked transitions.
- Exact operator task name and flag shape, provided it is one coherent break-glass surface and uses the context transition API.
- Exact notification module placement and mail content, subject to Phase 9 delivery-mode implementation and official Swoosh/Phoenix guidance during research.

### Folded Todos
None.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Locked Phase Requirements
- `.planning/phases/10-user-status-administration/10-SPEC.md` - Locked requirements, boundaries, constraints, acceptance criteria, and transition graph for MAIL-07 and USER-01 through USER-05.
- `.planning/ROADMAP.md` - Phase 10 roadmap goal, dependency on Phase 9, success criteria, and milestone boundary.
- `.planning/REQUIREMENTS.md` - MAIL-07 and USER-01 through USER-05 traceability.
- `.planning/PROJECT.md` - SSH-first product direction, v1.2 pre-alpha gap closure goal, and out-of-scope browser/reach features.
- `.planning/STATE.md` - Current milestone position and recent decisions affecting Phase 10.

### Delivery Mode Dependency
- `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-CONTEXT.md` - Delivery-mode decisions that Phase 10 consumes for SMTP/no-email branching and honest copy.
- `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-SPEC.md` - Locked MAIL-01 through MAIL-06 delivery-mode contract if Phase 9 plans or implementation are not yet available.

### Codebase Maps And Domain Docs
- `docs/DATA_MODEL.md` - User schema, persistence conventions, enum-like string fields, and deletion/anonymization invariants.
- `.planning/codebase/ARCHITECTURE.md` - SSH/TUI/domain layering, context boundaries, PubSub, and screen command routing patterns.
- `.planning/codebase/CONVENTIONS.md` - Context API, changeset, authorization, module, docs, and precommit conventions.
- `.planning/codebase/TESTING.md` - ExUnit organization, TUI screen test patterns, global config test isolation, and process-test constraints.
- `.planning/codebase/INTEGRATIONS.md` - Current outgoing integration state and available Swoosh/Oban context.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.Accounts.User` already owns `@valid_statuses`, `field :status, Ecto.Enum`, and `status_changeset/2`; Phase 10 extends this path to include `:rejected`.
- `priv/repo/migrations/20260418010000_add_status_to_users.exs` uses a string status column plus a `status_must_be_valid` check constraint; Phase 10 should follow that migration style.
- `Foglet.Accounts` already owns registration, pending registration, authentication, password reset, role update, deletion, invite actions, and token helpers, making it the natural status-transition boundary.
- `Foglet.Authorization` already implements `Bodyguard.Policy`, denies pending/suspended/deleted actors before role checks, and provides the sysop-only authorization model to extend.
- `Foglet.TUI.Screens.Sysop` already delegates tab bodies to submodules and uses `Foglet.TUI.Screens.Sysop.State` for screen-local tab state.
- Existing Mix tasks under `lib/mix/tasks/foglet.user.*.ex` provide the break-glass command style for user creation, role promotion, and password reset.
- `Foglet.TUI.Screens.Login` already blocks `:pending` and `:suspended` after successful password authentication; it needs a `:rejected` branch and delivery-honest copy.
- `Foglet.TUI.Screens.Register` already creates pending users for sysop-approved registration mode; its pending-approval copy must align with actual Phase 10 notification behavior.

### Established Patterns
- Domain mutations live in `Foglet.*` contexts. TUI screens render and dispatch, but do not own direct Repo mutations.
- Actor-aware side effects use `Bodyguard.permit/4`; `Bodyguard.permit?/4` is advisory UI only.
- Soft-deleted users remain rows with `deleted_at`; normal account administration should reject deleted targets rather than reusing deletion as a status state.
- TUI shell screens keep reusable tab behavior in submodules and state structs instead of growing monolithic render/event code.
- TUI screen tests construct minimal `%Foglet.TUI.App{}` state and inspect rendered text/return commands rather than starting a full SSH session.
- Tests that touch global config/delivery state should run `async: false` and isolate ETS/config state explicitly.

### Integration Points
- Migration, schema, changeset, fixtures, docs, and tests for adding `:rejected`.
- `Foglet.Authorization` valid action list and policy tests for sysop-only status administration.
- `Foglet.Accounts` status-transition APIs, queries/list helpers for Sysop `USERS`, notification hooks, and focused domain tests.
- `Foglet.TUI.Screens.Sysop.State`, a new users tab submodule, `Sysop.render/1`, `delegate_to_active_tab/3`, and TUI screen tests.
- Existing login/register screens and tests for pending/rejected/suspended/active/reactivated copy.
- One new `mix foglet.user.status`-style task and mirrored tests under `test/mix/tasks/`.
- Phase 9 delivery-mode APIs and Swoosh mailer/test adapter once available in the working tree.
</code_context>

<specifics>
## Specific Ideas

No external product reference was provided. The chosen direction is conservative and codebase-native: keep status truth in Accounts, keep administration terminal-first, keep the transition graph narrow, and make all email-related output describe what Foglet actually attempted.
</specifics>

<deferred>
## Deferred Ideas

- `rejected -> active` appeals or reopening rejected registrations.
- `suspended -> rejected` and arbitrary status editing.
- Status changes for soft-deleted users.
- Rich user history, audit timeline, invite history, moderation history, or case-management views.
- Bulk status actions, search/filter polish, pagination polish, role changes, profile editing, and board subscription controls.
- End-user browser administration or approval workflows.
- Webhook notifications, email digests, delivery retry queues, outbound delivery logs, and durable background delivery processing.

### Reviewed Todos (not folded)
None.
</deferred>

---

*Phase: 10-user-status-administration*
*Context gathered: 2026-04-24*
