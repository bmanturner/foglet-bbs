# Phase 10: User Status Administration - Research

**Researched:** 2026-04-24 [VERIFIED: system date]  
**Domain:** Elixir/Phoenix Accounts context status transitions, Bodyguard authorization, SSH/TUI sysop administration, Mix break-glass tasks, Swoosh notification integration [VERIFIED: `.planning/phases/10-user-status-administration/10-SPEC.md`]  
**Confidence:** HIGH [VERIFIED: codebase inspection; CITED: https://hexdocs.pm/ecto/Ecto.Enum.html; CITED: https://hexdocs.pm/bodyguard/Bodyguard.Policy.html]

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
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

### Deferred Ideas (OUT OF SCOPE)
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
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MAIL-07 | Pending user receives approval or rejection notification by email when SMTP delivery is configured. | Use Phase 9's Swoosh delivery-mode contract, attempt notification after a valid `pending -> active` or `pending -> rejected` transition, and return delivery-warning metadata without rolling back the status update. [VERIFIED: `.planning/REQUIREMENTS.md`; VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`; CITED: https://hexdocs.pm/swoosh/Swoosh.html] |
| USER-01 | Sysop can list pending users from the Sysop `USERS` tab. | Add `Accounts` list helpers for non-deleted users and render them through a new Sysop users submodule/state, matching existing delegated tab patterns. [VERIFIED: `lib/foglet_bbs/tui/screens/sysop.ex`; VERIFIED: `lib/foglet_bbs/tui/screens/sysop/state.ex`] |
| USER-02 | Sysop can approve or reject a pending user through an actor-aware Accounts context API. | Add public `Foglet.Accounts` transition APIs using `Bodyguard.permit/4`, `User.status_changeset/2`, and locked transition validation. [VERIFIED: `lib/foglet_bbs/accounts.ex`; VERIFIED: `lib/foglet_bbs/accounts/user.ex`; CITED: https://hexdocs.pm/bodyguard/Bodyguard.Policy.html] |
| USER-03 | Sysop can suspend or reactivate an existing user through an actor-aware Accounts context API. | Reuse the same transition boundary for `active -> suspended` and `suspended -> active`; deleted and invalid-state targets must return tagged failures. [VERIFIED: `.planning/phases/10-user-status-administration/10-SPEC.md`; VERIFIED: `lib/foglet_bbs/accounts.ex`] |
| USER-04 | Sysop can approve, reject, suspend, or reactivate users through a break-glass Mix task. | Add one `mix foglet.user.status`-style task that parses handle and target status, starts the app, and calls Accounts APIs instead of Repo updates. [VERIFIED: `lib/mix/tasks/foglet.user.promote.ex`; VERIFIED: `test/mix/tasks/foglet_user_promote_test.exs`; CITED: https://hexdocs.pm/mix/Mix.html] |
| USER-05 | Pending, rejected, suspended, and reactivated users see accurate login outcomes and TUI copy. | Extend Login status dispatch with a `:rejected` branch and replace false notification copy with delivery-mode/result-aware text. [VERIFIED: `lib/foglet_bbs/tui/screens/login.ex`; VERIFIED: `lib/foglet_bbs/tui/screens/register.ex`] |
</phase_requirements>

## Summary

Phase 10 should be implemented as an Accounts-owned status state machine with terminal and Mix surfaces as clients. [VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`] The existing system already has string-backed `users.status` via `Ecto.Enum`, a database check constraint, Bodyguard policy enforcement, delegated Sysop tab modules, and break-glass Mix task conventions. [VERIFIED: `lib/foglet_bbs/accounts/user.ex`; VERIFIED: `priv/repo/migrations/20260418010000_add_status_to_users.exs`; VERIFIED: `lib/foglet_bbs/authorization.ex`; VERIFIED: `lib/foglet_bbs/tui/screens/sysop.ex`; VERIFIED: `lib/mix/tasks/foglet.user.promote.ex`]

The standard architecture is narrow: update persistence and schema constraints first, add public actor-aware transition APIs in `Foglet.Accounts`, extend `Foglet.Authorization` with a sysop-only status action, consume those APIs from a new Sysop `USERS` tab submodule and one Mix task, then align Login/Register copy and approval/rejection delivery behavior with Phase 9's delivery-mode contract. [VERIFIED: `CLAUDE.md`; VERIFIED: `.planning/phases/10-user-status-administration/10-SPEC.md`; VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-RESEARCH.md`]

The biggest risks are treating `:rejected` like deletion, letting TUI or Mix bypass the Accounts transition graph, rolling back valid status changes because email failed, missing authorization for inactive actors, and adding browser or case-management admin scope. [VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`; VERIFIED: `CLAUDE.md`]

**Primary recommendation:** Use `Foglet.Accounts.transition_user_status/3` or equivalent as the single boundary for approve/reject/suspend/reactivate, backed by `Ecto.Enum`, check constraints, `Bodyguard.permit/4`, `Repo.transact/1`, and Swoosh delivery results from Phase 9. [VERIFIED: codebase inspection; CITED: https://hexdocs.pm/ecto/Ecto.Enum.html; CITED: https://hexdocs.pm/bodyguard/Bodyguard.Policy.html; CITED: https://hexdocs.pm/swoosh/Swoosh.html]

## Project Constraints (from CLAUDE.md)

- Foglet is SSH-first; Phoenix is infrastructure for endpoint, PubSub, telemetry, LiveDashboard, and future structured clients, not an end-user browser workflow surface. [VERIFIED: `CLAUDE.md`]
- Use `rtk` as the shell prefix for repo commands such as `rtk mix test` and `rtk git status`. [VERIFIED: `CLAUDE.md`]
- Domain workflows belong in `Foglet.*` contexts, not controllers, SSH callbacks, or TUI render functions. [VERIFIED: `CLAUDE.md`]
- `Foglet.Accounts` owns users, auth, roles, invites, tokens, SSH keys, and deletion. [VERIFIED: `CLAUDE.md`]
- Postgres is authoritative for durable state; ETS/process state must be reconstructable after restart. [VERIFIED: `CLAUDE.md`]
- Context modules own transactions, authorization checks, preload choices, PubSub side effects, and cross-schema invariants. [VERIFIED: `CLAUDE.md`]
- Actor-triggered side effects must use `Bodyguard.permit/4`; `Bodyguard.permit?/4` is advisory UI only. [VERIFIED: `CLAUDE.md`]
- Stable authorization scope shapes are `:site` and `{:board, board_id}`. [VERIFIED: `CLAUDE.md`]
- For TUI flows, global navigation stays in `Foglet.TUI.App`, screen-local state stays in screens or sibling `state.ex`, and data/mutations stay in domain contexts. [VERIFIED: `CLAUDE.md`]
- For migrations/schemas, read `docs/DATA_MODEL.md`, use `Foglet.Schema`, and keep migration, schema, changeset, context, fixtures, and tests aligned. [VERIFIED: `CLAUDE.md`; VERIFIED: `docs/DATA_MODEL.md`]
- Tests should use `start_supervised!/1` for processes and avoid `Process.sleep/1`; synchronize through monitors, messages, or `:sys.get_state/1`. [VERIFIED: `CLAUDE.md`; VERIFIED: `.planning/codebase/TESTING.md`]
- Run `mix precommit` when implementation changes are complete; it runs compile with warnings as errors, formatter, Credo, Sobelow, and Dialyzer. [VERIFIED: `CLAUDE.md`; VERIFIED: `mix.exs`]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| User status persistence | Database / Storage | API / Backend (`Foglet.Accounts.User`) | `users.status` is a persisted string column with an Ecto enum schema field and DB check constraint. [VERIFIED: `lib/foglet_bbs/accounts/user.ex`; VERIFIED: `priv/repo/migrations/20260418010000_add_status_to_users.exs`; CITED: https://hexdocs.pm/ecto/Ecto.Enum.html] |
| Status transition graph | API / Backend (`Foglet.Accounts`) | Database / Storage | Transitions are business rules and must be enforced before update persistence. [VERIFIED: `CLAUDE.md`; VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`] |
| Status authorization | API / Backend (`Foglet.Authorization`) | TUI advisory rendering | Bodyguard is the trust boundary for actor-triggered side effects; UI visibility is not authorization. [VERIFIED: `lib/foglet_bbs/authorization.ex`; CITED: https://hexdocs.pm/bodyguard/Bodyguard.Policy.html] |
| Sysop user administration | SSH TUI | API / Backend (`Foglet.Accounts`) | The Sysop screen owns terminal selection/rendering, while user queries and mutations must stay in Accounts. [VERIFIED: `lib/foglet_bbs/tui/screens/sysop.ex`; VERIFIED: `CLAUDE.md`] |
| Break-glass status administration | Mix task / Operator CLI | API / Backend (`Foglet.Accounts`) | Existing break-glass tasks are CLI shells that start the app and call context functions. [VERIFIED: `lib/mix/tasks/foglet.user.promote.ex`; VERIFIED: `lib/mix/tasks/foglet.user.reset_password.ex`] |
| Approval/rejection notification | API / Backend (`Foglet.Accounts` + Phase 9 mailer) | External provider through Swoosh | Phase 9 owns delivery mode and mailer setup; Phase 10 should only call delivery APIs and report attempted/skipped/failed results. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-RESEARCH.md`; CITED: https://hexdocs.pm/swoosh/Swoosh.html] |
| Login outcome copy | SSH TUI Login screen | API / Backend (`Accounts.post_login_screen/1`) | Login owns modal copy and session promotion, but account status is persisted domain state. [VERIFIED: `lib/foglet_bbs/tui/screens/login.ex`; VERIFIED: `lib/foglet_bbs/accounts.ex`] |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Elixir / Mix | 1.19.5 / OTP 28 | Runtime, tests, and custom operator tasks. | Installed locally and used by this repo's Mix project and task tests. [VERIFIED: `elixir --version`; VERIFIED: `mix --version`; VERIFIED: `mix.exs`] |
| Phoenix | `1.8.5` | PubSub, endpoint, telemetry infrastructure. | Already locked in `mix.lock`; Phase 10 should not add web workflows. [VERIFIED: `mix.lock`; VERIFIED: `CLAUDE.md`] |
| Ecto / Ecto SQL | `3.13.5` | Schema enum casting, changesets, migrations, constraints, Repo transactions. | `Ecto.Enum` is the current project pattern for `users.status`; official docs define atom-to-string/integer mapping. [VERIFIED: `mix.lock`; VERIFIED: `lib/foglet_bbs/accounts/user.ex`; CITED: https://hexdocs.pm/ecto/Ecto.Enum.html] |
| PostgreSQL via `postgrex` | locked transitively by `ecto_sql` | Durable user status storage and check constraints. | Existing migration uses a string status column plus `status_must_be_valid` check constraint. [VERIFIED: `priv/repo/migrations/20260418010000_add_status_to_users.exs`; CITED: https://hexdocs.pm/ecto_sql/Ecto.Migration.html] |
| Bodyguard | `2.4.3` | Actor-aware authorization at context boundaries. | Existing policy module implements `Bodyguard.Policy`; official docs say policy callbacks are used through `Bodyguard.permit/4`. [VERIFIED: `mix.lock`; VERIFIED: `lib/foglet_bbs/authorization.ex`; CITED: https://hexdocs.pm/bodyguard/Bodyguard.Policy.html] |
| Raxol | local path `vendor/raxol` | Terminal UI rendering and input lifecycle. | Existing TUI screens and widgets use Raxol render trees and screen behavior. [VERIFIED: `mix.exs`; VERIFIED: `.planning/codebase/ARCHITECTURE.md`] |
| Swoosh | Phase 9 dependency, researched as `1.25.0` | Approval/rejection notification delivery in email mode. | Phase 10 consumes Phase 9's delivery-mode contract and Swoosh mailer, rather than adding another notification stack. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-RESEARCH.md`; CITED: https://hexdocs.pm/swoosh/Swoosh.html] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `OptionParser` | Elixir stdlib | Parse `--status` or equivalent flags for the Mix task. | Existing `foglet.user.promote` and reset tasks use `OptionParser.parse!/2`. [VERIFIED: `lib/mix/tasks/foglet.user.promote.ex`] |
| `Mix.shell/0` / `Mix.Shell.Process` | Mix 1.19.5 | Operator output and task test assertions. | Official Mix docs describe swappable shell modules for testing; existing task tests use this style. [CITED: https://hexdocs.pm/mix/Mix.html; VERIFIED: `test/mix/tasks/foglet_user_promote_test.exs`] |
| `Swoosh.TestAssertions` | Swoosh Phase 9 dependency | Assert approval/rejection emails in ExUnit. | Phase 9 research selects Swoosh test adapter for direct delivery tests. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-RESEARCH.md`; CITED: https://hexdocs.pm/swoosh/Swoosh.html] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| String-backed `Ecto.Enum` status | PostgreSQL enum type | Locked out for this phase; project pattern allows adding values through migration constraints and changeset validation. [VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`; CITED: https://hexdocs.pm/ecto/Ecto.Enum.html] |
| Accounts transition APIs | Direct `Repo.update` from TUI/Mix | Violates context boundary and risks authorization bypass. [VERIFIED: `CLAUDE.md`; VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`] |
| Single status task | Separate approve/reject/suspend/reactivate tasks | Separate tasks add CLI surface area without reducing domain complexity; one task matches locked preference. [VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`] |
| Synchronous Swoosh attempt | Oban-delivered background notifications | Durable delivery queues/logs/retries are explicitly deferred; immediate attempt plus warning result is sufficient. [VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`; VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-RESEARCH.md`] |

**Installation:**
```elixir
# No new Phase 10 dependency is required beyond Phase 9's Swoosh stack.
# Existing deps used by Phase 10:
{:ecto_sql, "~> 3.13"}
{:bodyguard, "~> 2.4"}
{:raxol, path: "vendor/raxol"}
```

**Version verification:** `mix.lock` verifies `ecto` `3.13.5`, `ecto_sql` `3.13.5`, `bodyguard` `2.4.3`, `phoenix` `1.8.5`, and `oban` `2.21.1`; `mix.exs` verifies `raxol` is a local path dependency. [VERIFIED: `mix.lock`; VERIFIED: `mix.exs`]

## Architecture Patterns

### System Architecture Diagram

```text
Registration in sysop-approved mode
  -> Foglet.Accounts.register_pending_user(attrs)
  -> users.status = "pending"
  -> Phase 9/10 delivery mode check
  -> if email mode: attempt sysop pending-user notification
  -> if no-email mode: skip notification and render honest copy

Sysop USERS tab / Mix status task
  -> select target handle/id + requested target status
  -> Foglet.Accounts status transition API
  -> load non-deleted target user
  -> Bodyguard.permit(Foglet.Authorization, :manage_user_status, actor, :site)
  -> validate locked transition graph
     -> invalid/forbidden/not_found/deleted: return tagged error, no DB update, no email
     -> valid: Repo.transact update via User.status_changeset
  -> for pending approval/rejection only:
     -> read Phase 9 delivery mode
     -> email mode: Swoosh approval/rejection notification attempt
     -> no-email mode: skipped notification result
  -> return tagged success with status + delivery outcome
  -> TUI/Mix render terminal/operator copy from tags, not parsed strings

Login
  -> Accounts.authenticate_by_password(handle, password)
  -> inspect persisted user.status
     -> active: Accounts.post_login_screen(user) -> verify or main_menu
     -> pending: pending approval modal
     -> rejected: rejected registration modal
     -> suspended: suspended account modal
```

### Recommended Project Structure

```text
lib/
├── foglet_bbs/
│   ├── accounts.ex                         # status list/query APIs and transition boundary
│   ├── accounts/
│   │   ├── user.ex                         # add :rejected to @valid_statuses
│   │   └── email.ex                        # Phase 9/10 notification builders if not already present
│   ├── authorization.ex                    # sysop-only :manage_user_status action
│   └── tui/screens/
│       ├── login.ex                        # pending/rejected/suspended/active dispatch
│       ├── register.ex                     # pending copy and sysop notification call/result
│       └── sysop/
│           ├── state.ex                    # add users_view field
│           └── users_view.ex               # USERS tab state/render/key handling
├── mix/tasks/
│   └── foglet.user.status.ex               # one break-glass status task
priv/repo/migrations/
└── *_add_rejected_user_status.exs          # replace users status check constraint
test/
├── foglet_bbs/accounts/user_test.exs
├── foglet_bbs/accounts/accounts_test.exs
├── foglet_bbs/authorization_test.exs
├── foglet_bbs/tui/screens/login_test.exs
├── foglet_bbs/tui/screens/register_test.exs
├── foglet_bbs/tui/screens/sysop_test.exs
└── mix/tasks/foglet_user_status_test.exs
```

### Pattern 1: String-Backed Status Enum With DB Constraint

**What:** Add `:rejected` to `@valid_statuses`, keep `field :status, Ecto.Enum`, and update the `users.status` check constraint to include `'rejected'`. [VERIFIED: `lib/foglet_bbs/accounts/user.ex`; VERIFIED: `priv/repo/migrations/20260418010000_add_status_to_users.exs`; CITED: https://hexdocs.pm/ecto/Ecto.Enum.html]  
**When to use:** This is the locked persistence approach for Phase 10. [VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`]

```elixir
# Source: https://hexdocs.pm/ecto/Ecto.Enum.html + verified Foglet User schema
@valid_statuses [:active, :pending, :rejected, :suspended]

schema "users" do
  field :status, Ecto.Enum, values: @valid_statuses, default: :active
end

def status_changeset(user, attrs) do
  user
  |> cast(attrs, [:status])
  |> validate_required([:status])
  |> validate_inclusion(:status, @valid_statuses)
end
```

### Pattern 2: Accounts-Owned Transition Boundary

**What:** Resolve the target, authorize the actor, validate the transition graph, persist through `User.status_changeset/2`, and only then attempt delivery. [VERIFIED: `CLAUDE.md`; VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`]  
**When to use:** Every TUI and Mix status operation. [VERIFIED: `.planning/phases/10-user-status-administration/10-SPEC.md`]

```elixir
# Source: verified Foglet context conventions + Bodyguard docs
@spec transition_user_status(User.t(), User.t() | String.t(), atom()) ::
        {:ok, %{user: User.t(), delivery: atom()}}
        | {:error, :forbidden | :not_found | :deleted | :invalid_transition | Ecto.Changeset.t()}
def transition_user_status(%User{} = actor, target_or_id, target_status) do
  with {:ok, target} <- fetch_status_target(target_or_id),
       :ok <- Bodyguard.permit(Foglet.Authorization, :manage_user_status, actor, :site),
       :ok <- permit_status_transition(target.status, target_status),
       {:ok, updated} <- update_status(target, target_status) do
    {:ok, %{user: updated, delivery: maybe_deliver_status_notice(target, updated)}}
  end
end
```

### Pattern 3: Sysop Tab Delegation

**What:** `Sysop` remains the tab router; `UsersView` owns state/render/key handling; Accounts owns queries/mutations. [VERIFIED: `lib/foglet_bbs/tui/screens/sysop.ex`; VERIFIED: `lib/foglet_bbs/tui/screens/sysop/boards_view.ex`]  
**When to use:** Replacing the `USERS` placeholder. [VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`]

```elixir
# Source: verified Sysop delegation pattern
defp render_tab_body("USERS", ss, theme) do
  case ss.users_view do
    nil -> placeholder("Press any key to load users.", theme)
    view -> UsersView.render(view, theme)
  end
end

defp delegate_to_active_tab(event, state, ss) do
  case Enum.at(State.tab_labels(ss), ss.active_tab) do
    "USERS" -> delegate_to_submodule(event, state, ss, :users_view, UsersView)
    other -> delegate_existing_tabs(other, event, state, ss)
  end
end
```

### Pattern 4: Break-Glass Mix Task As Context Client

**What:** Parse one handle and one target status, start `:foglet_bbs`, resolve a sysop actor or explicit system actor policy, call the same Accounts transition API, and print tagged outcome text. [VERIFIED: `lib/mix/tasks/foglet.user.promote.ex`; VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`]  
**When to use:** `USER-04` operator path. [VERIFIED: `.planning/REQUIREMENTS.md`]

```elixir
# Source: verified Foglet Mix task style + Mix docs
def run(args) do
  {:ok, _} = Application.ensure_all_started(:foglet_bbs)
  {opts, [handle]} = OptionParser.parse!(args, strict: [status: :string])

  case Accounts.transition_user_status(operator_actor(), handle, Keyword.fetch!(opts, :status)) do
    {:ok, %{user: user, delivery: delivery}} ->
      Mix.shell().info("Updated #{user.handle} to #{user.status}; notification: #{delivery}")

    {:error, reason} ->
      Mix.shell().error("Status update failed: #{inspect(reason)}")
      exit({:shutdown, 1})
  end
end
```

### Anti-Patterns to Avoid

- **Direct `Repo.update` from TUI or Mix:** Bypasses authorization, transition graph, delivery result handling, and invariant tests. [VERIFIED: `CLAUDE.md`; VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`]
- **Treating rejected as deleted:** Rejected users must remain non-deleted rows so handles/emails stay reserved and login can report rejection. [VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`]
- **Permitting arbitrary status edits:** Only `pending -> active`, `pending -> rejected`, `active -> suspended`, and `suspended -> active` are valid. [VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`]
- **Notification before persistence:** Invalid/forbidden/not-found/deleted targets must not send mail. [VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`]
- **Rollback on mail failure by default:** The locked default is status succeeds and callers receive a delivery warning. [VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`]
- **Browser admin:** End-user/browser administration is out of scope and contradicts the SSH-first project boundary. [VERIFIED: `CLAUDE.md`; VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Enum persistence | Custom atom/string conversion or ad hoc string validation | `Ecto.Enum` plus check constraint | Official Ecto enum maps atoms to persisted strings/integers safely, and the project already uses it for `users.status`. [VERIFIED: `lib/foglet_bbs/accounts/user.ex`; CITED: https://hexdocs.pm/ecto/Ecto.Enum.html] |
| Authorization | Role checks in TUI, Mix task, or query helpers | `Bodyguard.permit/4` against `Foglet.Authorization` | Official Bodyguard pattern is policy callbacks through `permit/4`; project rules require it before side effects. [VERIFIED: `CLAUDE.md`; CITED: https://hexdocs.pm/bodyguard/Bodyguard.Policy.html] |
| Status state machine | Scattered `case` statements in screens/tasks | One Accounts transition helper/table | Prevents inconsistent valid transitions and side effects. [VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`] |
| Email delivery | Custom SMTP/API calls or direct provider clients | Phase 9 `Foglet.Mailer` / Swoosh delivery functions | Swoosh already supplies provider adapters and test support. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-RESEARCH.md`; CITED: https://hexdocs.pm/swoosh/Swoosh.html] |
| Operator CLI parsing | Custom string parser | `OptionParser.parse!/2` and existing Mix shell patterns | Existing tasks already use this style and Mix shell is testable. [VERIFIED: `lib/mix/tasks/foglet.user.promote.ex`; CITED: https://hexdocs.pm/mix/Mix.html] |
| Sysop UI framework | New modal/router framework for Users | Existing Sysop tab delegation and Raxol widgets | The shell/router/submodule pattern already exists and is locked for this phase. [VERIFIED: `lib/foglet_bbs/tui/screens/sysop.ex`; VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`] |

**Key insight:** The complex part is not UI rendering; it is keeping persistence, authorization, state transitions, login outcomes, and notification side effects in one Accounts-owned flow with typed results. [VERIFIED: `.planning/phases/10-user-status-administration/10-SPEC.md`; VERIFIED: `CLAUDE.md`]

## Common Pitfalls

### Pitfall 1: Schema Allows Rejected But Database Rejects It
**What goes wrong:** `User.status_changeset/2` accepts `:rejected`, but the existing `status_must_be_valid` DB constraint still allows only `active`, `pending`, and `suspended`. [VERIFIED: `lib/foglet_bbs/accounts/user.ex`; VERIFIED: `priv/repo/migrations/20260418010000_add_status_to_users.exs`]  
**Why it happens:** Ecto enum validation and database constraints are separate enforcement layers. [CITED: https://hexdocs.pm/ecto/Ecto.Enum.html; CITED: https://hexdocs.pm/ecto_sql/Ecto.Migration.html]  
**How to avoid:** Update schema, migration constraint, tests, fixtures, and docs in the same plan. [VERIFIED: `CLAUDE.md`; VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`]  
**Warning signs:** Tests only assert changeset validity and do not insert/reload a rejected user. [VERIFIED: `.planning/codebase/TESTING.md`]

### Pitfall 2: Break-Glass Task Bypasses Accounts
**What goes wrong:** Operator CLI can create invalid transitions or skip notification/copy behavior. [VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`]  
**Why it happens:** Existing promote task directly calls `Accounts.update_role/2`; status administration has more invariants than role assignment. [VERIFIED: `lib/mix/tasks/foglet.user.promote.ex`; VERIFIED: `.planning/phases/10-user-status-administration/10-SPEC.md`]  
**How to avoid:** The new task should be a thin adapter around the same Accounts status API used by TUI. [VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`]  
**Warning signs:** New task imports `Repo`, `Ecto.Changeset.change/2`, or calls `User.status_changeset/2` directly. [VERIFIED: `CLAUDE.md`]

### Pitfall 3: Inactive Actors Are Accidentally Authorized
**What goes wrong:** A pending, rejected, suspended, or deleted actor can change another user's status. [VERIFIED: `lib/foglet_bbs/authorization.ex`]  
**Why it happens:** Existing authorization blocks pending and suspended but does not yet know about `:rejected`. [VERIFIED: `lib/foglet_bbs/authorization.ex`; VERIFIED: `lib/foglet_bbs/accounts/user.ex`]  
**How to avoid:** Extend invalid actor guards and `scopes_for/2` to include `:rejected`, then add policy tests. [VERIFIED: `test/foglet_bbs/authorization_test.exs`]  
**Warning signs:** `:rejected` appears only in Accounts tests, not authorization tests. [VERIFIED: test file inspection]

### Pitfall 4: Delivery Failure Rolls Back Account Decision
**What goes wrong:** A valid approval/rejection is undone because SMTP delivery fails. [VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`]  
**Why it happens:** Delivery is placed inside a DB transaction or `with` chain as a required step. [ASSUMED]  
**How to avoid:** Persist valid status first, then attempt delivery and return `{:ok, %{delivery: :failed}}` or equivalent warning metadata. [VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`]  
**Warning signs:** Domain tests expect status to remain pending after a simulated Swoosh failure. [VERIFIED: `.planning/phases/10-user-status-administration/10-SPEC.md`]

### Pitfall 5: Login Copy Promises Email In No-Email Mode
**What goes wrong:** Pending/rejected users see copy saying they will be emailed even when no delivery was attempted or configured. [VERIFIED: `lib/foglet_bbs/tui/screens/login.ex`; VERIFIED: `lib/foglet_bbs/tui/screens/register.ex`]  
**Why it happens:** Existing pending copy is hardcoded and predates Phase 9/10 delivery-mode work. [VERIFIED: `lib/foglet_bbs/tui/screens/login.ex`; VERIFIED: `lib/foglet_bbs/tui/screens/register.ex`]  
**How to avoid:** Branch terminal copy from Accounts/Config delivery results, not static strings. [VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`; VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-RESEARCH.md`]  
**Warning signs:** Strings like "You will be notified by email" remain unconditional. [VERIFIED: codebase grep]

### Pitfall 6: Users Tab Becomes a Monolith
**What goes wrong:** `Foglet.TUI.Screens.Sysop` grows query, selection, action, and modal logic directly. [VERIFIED: `lib/foglet_bbs/tui/screens/sysop.ex`]  
**Why it happens:** The existing `USERS` tab is a placeholder, so implementation can be added at the nearest function. [VERIFIED: `lib/foglet_bbs/tui/screens/sysop.ex`]  
**How to avoid:** Add a sibling `users_view.ex` and a `users_view` field in `Sysop.State`, mirroring `BoardsView`, `SiteForm`, `LimitsForm`, and `SystemSnapshot`. [VERIFIED: `lib/foglet_bbs/tui/screens/sysop.ex`; VERIFIED: `lib/foglet_bbs/tui/screens/sysop/state.ex`]  
**Warning signs:** `Sysop.render/1` calls `Accounts.list_*` or status transition APIs directly. [VERIFIED: `CLAUDE.md`]

## Code Examples

### Check Constraint Migration Shape

```elixir
# Source: verified existing migration + Ecto.Migration docs
def change do
  drop constraint(:users, :status_must_be_valid)

  create constraint(:users, :status_must_be_valid,
           check: "status IN ('active', 'pending', 'rejected', 'suspended')"
         )
end
```

### Transition Graph Helper

```elixir
# Source: Phase 10 locked transition graph
defp permit_status_transition(:pending, :active), do: :ok
defp permit_status_transition(:pending, :rejected), do: :ok
defp permit_status_transition(:active, :suspended), do: :ok
defp permit_status_transition(:suspended, :active), do: :ok
defp permit_status_transition(_from, _to), do: {:error, :invalid_transition}
```

### Authorization Action

```elixir
# Source: verified Foglet.Authorization shape + Bodyguard docs
@valid_actions [
  :manage_user_status
  | @existing_actions
]

def authorize(:manage_user_status, %User{role: :sysop}, :site), do: :ok
```

### Login Status Dispatch

```elixir
# Source: verified Login status branch shape
with {:ok, user} <- Accounts.authenticate_by_password(handle_value, password_value),
     :active <- user.status do
  screen = Accounts.post_login_screen(user)
  handle_auth_success(state, user, screen)
else
  :pending -> status_modal(state, "Your account is pending sysop approval.")
  :rejected -> status_modal(state, "Your registration was rejected. Contact the sysop.")
  :suspended -> status_modal(state, "Your account is suspended. Contact the sysop.")
  {:error, :invalid_credentials} -> invalid_credentials(state)
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Direct status changes in tests or ad hoc paths | Context-owned actor-aware transition API | Phase 10 locked 2026-04-24 | All TUI/Mix paths must use Accounts and test failure tags. [VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`] |
| Pending and suspended only | Active, pending, rejected, suspended with reactivation as `suspended -> active` | Phase 10 locked 2026-04-24 | Auth, authorization, login copy, fixtures, and constraints all need `:rejected`. [VERIFIED: `.planning/phases/10-user-status-administration/10-SPEC.md`] |
| Token/delivery comments say Phase 10 adds Swoosh | Phase 9 owns delivery mode and base Swoosh setup; Phase 10 consumes it for approval decisions | Roadmap v1.2 2026-04-24 | Planner must sequence Phase 10 after Phase 9 and avoid duplicate mailer setup. [VERIFIED: `.planning/ROADMAP.md`; VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-RESEARCH.md`] |
| Placeholder Sysop `USERS` tab | Delegated `UsersView` with Accounts calls | Phase 10 locked 2026-04-24 | `Sysop` remains shell/router and does not own user administration logic. [VERIFIED: `lib/foglet_bbs/tui/screens/sysop.ex`; VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`] |

**Deprecated/outdated:**
- Account module comments that say "Phase 10 adds Swoosh delivery" are outdated relative to v1.2 Phase 9 research; Phase 10 should consume delivery mode rather than create the base Swoosh stack. [VERIFIED: `lib/foglet_bbs/accounts.ex`; VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-RESEARCH.md`]
- Login/register copy that unconditionally promises an approval email is outdated because no-email mode is now explicit. [VERIFIED: `lib/foglet_bbs/tui/screens/login.ex`; VERIFIED: `lib/foglet_bbs/tui/screens/register.ex`; VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-CONTEXT.md`]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Delivery failure is most likely if email attempt is placed directly inside a DB transaction or required `with` chain. [ASSUMED] | Common Pitfalls | If implementation uses a different control flow, the concrete warning sign changes, but the rollback policy remains locked. |
| A2 | A single action atom such as `:manage_user_status` is sufficient instead of separate `:approve_user`, `:reject_user`, `:suspend_user`, and `:reactivate_user` atoms. [ASSUMED] | Code Examples | Separate atoms may improve audit clarity, but all must still be sysop-only and tested. |
| A3 | The Mix task can use a synthetic sysop/operator actor or resolve an existing sysop actor for authorization. [ASSUMED] | Architecture Patterns | Planner must choose an explicit break-glass actor model so `Bodyguard.permit/4` remains meaningful. |

## Open Questions

1. **Break-glass actor identity**
   - What we know: normal status transitions require actor-aware Accounts APIs and `Bodyguard.permit/4`. [VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`]
   - What's unclear: a Mix task has no logged-in TUI actor by default. [VERIFIED: `lib/mix/tasks/foglet.user.promote.ex`]
   - Recommendation: Planner should pick one explicit model: require `--actor HANDLE` for an existing sysop, or create a documented internal operator actor accepted only by the break-glass task path. [ASSUMED]

2. **Exact Phase 9 delivery result API**
   - What we know: Phase 9 research requires Accounts-level delivery functions and Swoosh test setup. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-RESEARCH.md`]
   - What's unclear: Phase 9 is not implemented in the current working tree, so exact function names and result atoms are not available. [VERIFIED: codebase grep]
   - Recommendation: Plan Phase 10 notification tasks after Phase 9 implementation or include an adapter task that aligns with whatever Phase 9 creates. [VERIFIED: `.planning/ROADMAP.md`]

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Elixir | Build/tests | yes | 1.19.5 / OTP 28 | none. [VERIFIED: `elixir --version`] |
| Mix | Tests and custom tasks | yes | 1.19.5 / OTP 28 | none. [VERIFIED: `mix --version`] |
| PostgreSQL/Ecto test database | Context/migration tests | project-configured | Ecto SQL 3.13.5 | `rtk mix test` alias creates/migrates test DB. [VERIFIED: `mix.exs`; VERIFIED: `mix.lock`] |
| Bodyguard | Authorization | yes | 2.4.3 | none. [VERIFIED: `mix.lock`] |
| Swoosh | Approval/rejection delivery | Phase 9 dependency, not present in current `mix.exs` | researched as 1.25.0 in Phase 9 | Phase 10 can implement status transitions first and defer notification adapter until Phase 9 lands. [VERIFIED: `mix.exs`; VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-RESEARCH.md`] |

**Missing dependencies with no fallback:**
- None for persistence, authorization, TUI, and Mix status administration. [VERIFIED: `mix.exs`; VERIFIED: `mix.lock`]

**Missing dependencies with fallback:**
- Swoosh is required for MAIL-07 email assertions, but Phase 10 is roadmap-dependent on Phase 9 where Swoosh is planned. [VERIFIED: `.planning/ROADMAP.md`; VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-RESEARCH.md`]

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit, built into Elixir; current local runtime Elixir/Mix is 1.19.5. [VERIFIED: `.planning/codebase/TESTING.md`; VERIFIED: `mix --version`] |
| Config file | `test/test_helper.exs`; `mix test` alias creates/migrates DB and seeds config. [VERIFIED: `test/test_helper.exs`; VERIFIED: `mix.exs`] |
| Quick run command | `rtk mix test test/foglet_bbs/accounts/user_test.exs test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/authorization_test.exs` |
| Full suite command | `rtk mix precommit` |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| MAIL-07 | SMTP/email mode attempts approval/rejection notification; no-email skips honestly; failure warns without rollback | integration | `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/tui/screens/register_test.exs` | partial; mailer tests depend on Phase 9. [VERIFIED: test file listing; VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-RESEARCH.md`] |
| USER-01 | Sysop `USERS` tab lists pending users | TUI unit | `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs` | yes, extend. [VERIFIED: `test/foglet_bbs/tui/screens/sysop_test.exs`] |
| USER-02 | Sysop approve/reject pending through Accounts | domain integration | `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/authorization_test.exs` | yes, extend. [VERIFIED: test file listing] |
| USER-03 | Sysop suspend/reactivate through Accounts | domain integration | `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/authorization_test.exs` | yes, extend. [VERIFIED: test file listing] |
| USER-04 | Break-glass task uses same transition rules | Mix task integration | `rtk mix test test/mix/tasks/foglet_user_status_test.exs` | no; add. [VERIFIED: `find test/mix/tasks`] |
| USER-05 | Login outcomes and copy for pending/rejected/suspended/active/reactivated | TUI/domain unit | `rtk mix test test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/screens/register_test.exs` | yes, extend. [VERIFIED: test file listing] |

### Sampling Rate

- **Per task commit:** Run the focused changed file, e.g. `rtk mix test test/foglet_bbs/accounts/accounts_test.exs`. [VERIFIED: `.planning/codebase/TESTING.md`]
- **Per wave merge:** Run all Phase 10 touched tests plus `rtk mix compile --warnings-as-errors`. [VERIFIED: `CLAUDE.md`]
- **Phase gate:** `rtk mix precommit` green before `/gsd-verify-work`. [VERIFIED: `CLAUDE.md`; VERIFIED: `mix.exs`]

### Wave 0 Gaps

- [ ] `test/mix/tasks/foglet_user_status_test.exs` - covers USER-04. [VERIFIED: `find test/mix/tasks`]
- [ ] Migration test or integration insert coverage for `:rejected` persistence - covers durable status acceptance. [VERIFIED: `test/foglet_bbs/accounts/user_test.exs`; VERIFIED: `.planning/phases/10-user-status-administration/10-SPEC.md`]
- [ ] Phase 9 mailer/test adapter availability - covers MAIL-07. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-RESEARCH.md`; VERIFIED: `mix.exs`]

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | yes | Login must block pending/rejected/suspended users and allow active/reactivated users through normal verification rules. [VERIFIED: `lib/foglet_bbs/tui/screens/login.ex`; VERIFIED: `.planning/phases/10-user-status-administration/10-SPEC.md`] |
| V3 Session Management | yes | Suspended/rejected users must not be promoted into authenticated TUI sessions. [VERIFIED: `lib/foglet_bbs/tui/screens/login.ex`; VERIFIED: `.planning/codebase/ARCHITECTURE.md`] |
| V4 Access Control | yes | Use `Bodyguard.permit/4` in Accounts before actor-triggered status side effects. [VERIFIED: `CLAUDE.md`; CITED: https://hexdocs.pm/bodyguard/Bodyguard.Policy.html] |
| V5 Input Validation | yes | Validate target status through `Ecto.Enum`, `User.status_changeset/2`, and locked transition graph. [VERIFIED: `lib/foglet_bbs/accounts/user.ex`; CITED: https://hexdocs.pm/ecto/Ecto.Enum.html] |
| V6 Cryptography | no direct change | Phase 10 does not add password hashing or token crypto; it reuses Phase 9 delivery and existing Accounts tokens where needed. [VERIFIED: `.planning/phases/10-user-status-administration/10-SPEC.md`; VERIFIED: `lib/foglet_bbs/accounts.ex`] |
| V9 Communications | yes | Approval/rejection email uses Phase 9 Swoosh delivery mode and must not expose provider secrets in DB config. [VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-RESEARCH.md`; VERIFIED: `CLAUDE.md`] |

### Known Threat Patterns for Phase 10

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Privilege escalation through UI-only checks | Elevation of Privilege | Context APIs call `Bodyguard.permit/4`; TUI visibility remains advisory. [VERIFIED: `CLAUDE.md`; CITED: https://hexdocs.pm/bodyguard/Bodyguard.Policy.html] |
| Invalid transition creating impossible account state | Tampering | Central transition graph in Accounts plus DB enum constraint. [VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`; VERIFIED: `priv/repo/migrations/20260418010000_add_status_to_users.exs`] |
| Rejected/deleted confusion | Information Disclosure / Integrity | Keep rejected rows non-deleted and reject status changes for deleted targets. [VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`] |
| False notification claims | Repudiation / Integrity | Terminal/Mix copy renders attempted/skipped/failed delivery result tags. [VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`; VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-RESEARCH.md`] |
| Suspended/rejected actor retains operator scopes | Elevation of Privilege | Update authorization actor guards and `scopes_for/2` to include `:rejected`. [VERIFIED: `lib/foglet_bbs/authorization.ex`] |

## Sources

### Primary (HIGH confidence)

- `CLAUDE.md` - SSH-first, context boundaries, authorization, TUI, migration, and test directives. [VERIFIED: local file]
- `.planning/phases/10-user-status-administration/10-CONTEXT.md` - locked implementation decisions and deferred scope. [VERIFIED: local file]
- `.planning/phases/10-user-status-administration/10-SPEC.md` - requirements, acceptance criteria, constraints, and transition graph. [VERIFIED: local file]
- `.planning/REQUIREMENTS.md` - MAIL-07 and USER-01 through USER-05 traceability. [VERIFIED: local file]
- `.planning/ROADMAP.md` - Phase 10 dependency on Phase 9 and success criteria. [VERIFIED: local file]
- `docs/DATA_MODEL.md` - account schema conventions and durable user row/deletion model. [VERIFIED: local file]
- `lib/foglet_bbs/accounts.ex`, `lib/foglet_bbs/accounts/user.ex` - current Accounts and User status implementation. [VERIFIED: local files]
- `lib/foglet_bbs/authorization.ex` - current Bodyguard policy shape. [VERIFIED: local file]
- `lib/foglet_bbs/tui/screens/sysop.ex`, `lib/foglet_bbs/tui/screens/sysop/state.ex` - Sysop tab delegation pattern. [VERIFIED: local files]
- `lib/mix/tasks/foglet.user.promote.ex`, `lib/mix/tasks/foglet.user.reset_password.ex` - current break-glass task style. [VERIFIED: local files]
- `mix.exs`, `mix.lock` - dependency versions and test/precommit aliases. [VERIFIED: local files]
- https://hexdocs.pm/ecto/Ecto.Enum.html - enum mapping and persistence behavior. [CITED: official docs]
- https://hexdocs.pm/ecto_sql/Ecto.Migration.html - check constraint migration support. [CITED: official docs]
- https://hexdocs.pm/bodyguard/Bodyguard.Policy.html - `authorize/3` and `permit/4` policy pattern. [CITED: official docs]
- https://hexdocs.pm/swoosh/Swoosh.html - Swoosh delivery stack consumed from Phase 9. [CITED: official docs]
- https://hexdocs.pm/mix/Mix.html - Mix shell behavior for task output/testing. [CITED: official docs]

### Secondary (MEDIUM confidence)

- `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-RESEARCH.md` - Phase 9 planned Swoosh/delivery-mode contract, not yet implemented in the current working tree. [VERIFIED: local file]

### Tertiary (LOW confidence)

- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all core libraries are in `mix.exs`/`mix.lock`, and Phase 9 Swoosh dependency is documented by prior research. [VERIFIED: `mix.exs`; VERIFIED: `mix.lock`; VERIFIED: `.planning/phases/09-delivery-modes-and-onboarding-honesty/09-RESEARCH.md`]
- Architecture: HIGH - phase context and project constraints are explicit, and current modules show matching boundaries. [VERIFIED: `CLAUDE.md`; VERIFIED: `lib/foglet_bbs/accounts.ex`; VERIFIED: `lib/foglet_bbs/tui/screens/sysop.ex`]
- Pitfalls: HIGH - most risks are directly visible in current code or locked decisions; only the exact delivery failure control-flow warning is assumed. [VERIFIED: codebase grep; VERIFIED: `.planning/phases/10-user-status-administration/10-CONTEXT.md`; ASSUMED]

**Research date:** 2026-04-24 [VERIFIED: system date]  
**Valid until:** 2026-05-01 for dependency/version assertions; codebase findings valid until Phase 9 or Phase 10 modifies the referenced modules. [ASSUMED]
