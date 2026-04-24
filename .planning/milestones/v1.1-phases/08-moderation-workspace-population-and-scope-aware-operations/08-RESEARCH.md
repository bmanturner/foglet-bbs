# Phase 08: Moderation Workspace Population and Scope-Aware Operations - Research

**Researched:** 2026-04-24
**Status:** Complete

## Executive Summary

Phase 8 should be planned as four tightly ordered slices:

1. Extend the oneliner domain with an actor-aware hide operation and visible-query exclusion tests.
2. Add the narrow `mod_actions` audit schema/context for `:hide_oneliner` only.
3. Populate Moderation tab state from app-owned domain reads, keeping placeholder-free honest states for workflows that do not exist yet.
4. Add main-menu selected-oneliner behavior and a required-reason modal that calls the domain hide operation.

The trust boundary must stay in domain contexts. Main-menu and Moderation screen checks are visibility affordances only; `Foglet.Oneliners.hide_entry/3` or equivalent must authorize through `Bodyguard.permit(Foglet.Authorization, :hide_oneliner, actor, scope)` before side effects.

## Current Implementation Findings

### Oneliners

- `lib/foglet_bbs/oneliners.ex` owns persisted oneliner creation and `list_recent_visible/1`.
- `lib/foglet_bbs/oneliners/entry.ex` already models hidden fields from Phase 7.
- `priv/repo/migrations/20260424024644_create_oneliners.exs` creates the current table.
- `test/foglet_bbs/oneliners/oneliners_test.exs` is the right place for hide authorization, reason validation, recent-visible exclusion, and side-effect tests.

Planning implication: put the hide mutation in `Foglet.Oneliners`, not the TUI. Programmatically set `hidden_by_id` and hidden fields inside the context; do not cast caller-provided moderator ids.

### Authorization

- `lib/foglet_bbs/authorization.ex` already knows `:hide_oneliner`.
- `test/foglet_bbs/authorization_test.exs` covers sysop/mod/user outcomes, including board-scope shape.
- Phase 1 context locked `scopes_for/2` as a list of `:site | {:board, board_id}` values.

Planning implication: Phase 8 should consume scopes as a list everywhere. A helper like `authorized_hide_scope(actor, entry)` may return the first permitted scope, but it must not collapse the API into `global_mod?`.

### Moderation Audit

- `docs/DATA_MODEL.md` documents `mod_actions` with `mod_user_id`, `action_kind`, `target_kind`, `target_id`, `reason`, and timestamps.
- No `mod_actions` migration, schema, or context exists yet.

Planning implication: create a narrow `Foglet.Moderation.Action` schema and `Foglet.Moderation` context function set for hide audits only. Avoid building reports, sanctions, or broad moderation APIs in this phase.

Recommended minimum API:

```elixir
Foglet.Moderation.record_hide_oneliner!(moderator, entry, reason, metadata)
Foglet.Moderation.list_actions_for_scopes(scopes, opts \\ [])
```

If board-scoped filtering needs a future hook, include nullable `scope_kind` / `scope_id` or metadata sufficient to filter site actions today and board actions later. If the implementation keeps only `target_kind/target_id`, document that oneliners are site-scoped in v1.1 and filter with `:site`.

### TUI App and Main Menu

- `lib/foglet_bbs/tui/app.ex` owns oneliner loading, modal composition, submit, and refresh.
- `default_domain_module(:oneliners)` already resolves to `Foglet.Oneliners`, with test injection through `session_context.domain`.
- `lib/foglet_bbs/tui/screens/main_menu.ex` renders a bounded oneliner panel but does not yet track selection.
- `test/foglet_bbs/tui/app_test.exs` and `test/foglet_bbs/tui/screens/main_menu_test.exs` already cover Phase 7 oneliner UI behavior.
- `Foglet.TUI.Widgets.Modal.Form` is the correct existing primitive for the required hide reason modal.

Planning implication: extend existing app-owned message flow rather than adding direct DB calls in `MainMenu`. The likely messages are:

- `{:select_oneliner, direction}` or explicit index messages from `MainMenu.handle_key/2`
- `{:open_hide_oneliner_modal, entry_id}`
- `{:submit_hide_oneliner, %{reason: reason}}`
- `{:oneliner_hidden, {:ok, entry_or_action}}`
- `{:oneliner_hidden, {:error, reason_or_changeset}}`

After a successful hide, refresh by queuing the existing `{:load_oneliners}` path or by removing the hidden entry from `state.recent_oneliners` and then refreshing.

### Moderation Workspace

- `lib/foglet_bbs/tui/screens/moderation.ex` renders the fixed tabs and delegates tab focus to `Foglet.TUI.Widgets.Input.Tabs`.
- `lib/foglet_bbs/tui/screens/moderation/state.ex` owns the fixed base tabs plus conditional shared `INVITES`.
- Shared invite tab modules under `lib/foglet_bbs/tui/screens/shared/` must remain intact.
- Current moderation tab bodies are Phase 8 placeholders.

Planning implication: add screen/app state for moderation data such as `mod_log`, `mod_users`, `mod_boards`, `mod_scopes`, and loading/error states. Use `Foglet.TUI.App` command/task patterns to load domain data, then render from state. Render functions should not query the database.

## Recommended Plan Breakdown

### Plan 08-01: Domain Hide and Audit Persistence

Build the durable trust-boundary pieces first:

- migration for `mod_actions`
- `Foglet.Moderation.Action`
- `Foglet.Moderation` narrow audit API
- `Foglet.Oneliners.hide_entry/3` or equivalent
- tests for authorization, blank reason rejection, no side effects on failure, recent-visible exclusion, and exactly one audit record on success

This plan should be Wave 1 and block TUI plans.

### Plan 08-02: Scope-Aware Moderation Data Loading and Tab Rendering

Populate the Moderation workspace without fake actions:

- app-owned load command for moderation data
- domain reads for log actions, read-only users, read-only board/scope context
- honest empty/unavailable states for `QUEUE` and `SANCTIONS`
- no fake approve, ban, sanction, delete, or board-management commands
- tests for mod/sysop scoped content and regular-user denial

This can depend on 08-01 for the log tab if it renders real hide audit history.

### Plan 08-03: Main-Menu Oneliner Selection and Hide Modal

Wire the user-facing hide affordance:

- selectable oneliner state in `Foglet.TUI.App`
- row focus styling in `MainMenu`
- moderator/sysop-only `[H] Hide oneliner` affordance when authorized
- required reason `Modal.Form`
- app command task calling the injected oneliners domain module
- success refresh/removal and error display
- tests in `app_test.exs` and `main_menu_test.exs`

This depends on 08-01.

### Plan 08-04: Integration, Layout, and Final Verification

Run the focused phase test set and final project gate:

- `mix test test/foglet_bbs/oneliners/oneliners_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/screens/moderation_test.exs`
- `mix precommit`
- update documentation only if schema/API names drift from `docs/DATA_MODEL.md`

## Validation Architecture

### Must-Test Requirements

| Requirement | Test Target | Proof |
|-------------|-------------|-------|
| MODR-05 hide action | `test/foglet_bbs/oneliners/oneliners_test.exs` | authorized mod/sysop hides visible entry |
| Domain auth trust boundary | `test/foglet_bbs/oneliners/oneliners_test.exs` | user/guest/pending/suspended actors get `{:error, :forbidden}` and row is unchanged |
| Required reason | `test/foglet_bbs/oneliners/oneliners_test.exs` | blank and whitespace reasons fail before persistence |
| Recent-visible exclusion | `test/foglet_bbs/oneliners/oneliners_test.exs` | hidden entry no longer appears; other entries remain newest first |
| Audit record | `test/foglet_bbs/moderation/moderation_test.exs` or oneliner test | success inserts exactly one `:hide_oneliner`; failures insert none |
| Moderation tab population | `test/foglet_bbs/tui/screens/moderation_test.exs` and `app_test.exs` | no Phase 8 placeholder copy, no fake mutation commands |
| Main-menu hide UX | `test/foglet_bbs/tui/screens/main_menu_test.exs` and `app_test.exs` | selected row, mod-only hide hint, required-reason modal, success refresh |
| Future scope shape | focused helper/domain tests | accepts `[:site]` and `[{:board, board_id}]` without boolean global-only APIs |

### Verification Commands

```bash
mix test test/foglet_bbs/oneliners/oneliners_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/screens/moderation_test.exs
mix precommit
```

## Risks and Plan Constraints

- Do not put DB reads inside `Foglet.TUI.Screens.Moderation.render/1` or `Foglet.TUI.Screens.MainMenu.render/1`.
- Do not accept `hidden_by_id`, moderator id, target id, or audit actor id from modal payloads.
- Do not use `String.to_atom/1` for action or target kinds; use `Ecto.Enum` values or explicit known atoms.
- Avoid full moderation scope creep. Reports, sanctions, broad user mutation, thread/post moderation, and board moderator assignment are out of scope.
- Keep `INVITES` tab behavior conditional and shared.
- If tests need supervised processes, use `start_supervised!/1` and deterministic synchronization, not `Process.sleep/1`.

## Research Complete

This phase is ready for executable planning. The planner should create concrete PLAN.md files for the four slices above and include security threat models because the phase mutates moderation state and enforces authorization.
