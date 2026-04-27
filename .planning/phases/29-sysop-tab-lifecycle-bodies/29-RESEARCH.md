# Phase 29: Sysop Tab Lifecycle & Bodies — Research

**Researched:** 2026-04-27
**Domain:** Foglet BBS TUI — Sysop screen lifecycle, App-level dispatch, USERS gating, INVITES surface, command-bar consistency
**Confidence:** HIGH (every claim verified against the current codebase; this phase touches only internal Elixir modules — no external libraries needed)

## Summary

Phase 29 is a fully internal TUI-shape change. There are no new domain rules,
no new schemas, no new authorization scopes, no new dependencies, and no
fast-moving external libraries to track. Every shape Phase 29 needs already
exists in the tree: `Foglet.TUI.Command.task/2` is in use, the Moderation
load/result/put-helper triad is the structural twin to copy, Phase 28's
Modal.Form `submit_state` machine and `Saved.` row are already in
`SiteForm.persist_payload/3`, `theme.selected.fg`/`bg` is already in use on
USERS, and `Foglet.Accounts.permit_status_transition/2` already encodes the
four canonical transitions Phase 29 needs to surface read-only.

The work is mechanical and pattern-driven:

1. Replace four `term() | nil` slots with a tagged `:not_loaded | :loading | {:loaded, struct} | {:error, reason}` enum.
2. Add four sibling clauses to `App.do_update/2` modeled exactly on
   `{:load_moderation_workspace}` / `{:moderation_workspace_loaded, _}` /
   `put_moderation_loading|snapshot|error`.
3. Trigger dispatch from two sites: (a) the active-tab branch of
   `Sysop.handle_key/2` after `Tabs.handle_event/2` resolves a tab change, and
   (b) a screen-entry guard. The closest existing precedent for (b) is
   `App.do_update({:navigate, :moderation}, _)` at `app.ex:321-322`, which
   chains into `{:load_moderation_workspace}`. **Recommended path:** add an
   analogous `screen == :sysop and ...` chain in `do_update({:navigate, :sysop}, _)` that fires the active-tab dispatch. The phase requires
   per-tab dispatch on tab switch regardless.
4. Expose `Foglet.Accounts.valid_status_transitions/1` derived from the
   private `permit_status_transition/2` clauses.
5. Rewrite five `@site_keys` description strings; rewrite `users_view.ex`
   footer + error-message helpers; add `[X] Revoke` advertising on Sysop
   command bar; convert two module attributes (`@key_bar`, `@key_list`) to
   render-time builders; refactor `jump_hint` to `"1-#{length(...)}"`.

**Primary recommendation:** Treat the Moderation load triad as the
authoritative reference implementation. Copy its shape four times (BOARDS,
LIMITS, SYSTEM, USERS), replace its `loading? + error` flat fields with the
proper tagged enum, and you are 60% of the phase. The remaining 40% is the
USERS predicate, INVITES focus + Revoke, the Site copy rewrites, and the
`1-N` helper.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Tab-lifecycle dispatch (`{:load_sysop_*}` tuples + result handlers) | App (`Foglet.TUI.App`) | — | App is the only sanctioned holder of `Foglet.TUI.Command.task/2`. CONTEXT.md D-04 forbids `Raxol.Core.Runtime.Command.task/1` from any `Sysop.*` module. |
| Tab-lifecycle slot storage | Screen state (`Foglet.TUI.Screens.Sysop.State`) | — | Screen-local UI state per AGENTS.md TUI rules; lives at `state.screen_state[:sysop]`. |
| Tab-switch trigger | Sysop screen (`handle_key/2`) | — | Tab navigation is screen-owned; the screen returns dispatch tuples in its `commands` list and `App.process_screen_commands/2` (`app.ex:1340-1359`) re-dispatches them through `do_update/2`. |
| Status-transition predicate | Domain context (`Foglet.Accounts`) | — | AGENTS.md: "domain truth lives in `Foglet.*`." Hands UsersView a read-only predicate; never duplicates the rule. |
| USERS keybind gating + from→to copy | Screen submodule (`Sysop.UsersView`) | Domain (`Foglet.Accounts.valid_status_transitions/1`) | Render-time advertising and copy formatting are presentation concerns. |
| INVITES focus highlight | Shared surface (`Shared.InvitesSurface`) | Theme (`Foglet.TUI.Theme`) | Surface is reusable across Account/Moderation/Sysop; selection-render uses theme slots. |
| INVITES `[X] Revoke` advertising | Sysop screen (`sysop_commands/1`) | Shared actions (`InvitesActions.handle_key/3`) | Command bar is screen-owned; the revoke side effect itself stays in InvitesActions. |
| Site description copy | Schema (`Foglet.Config.Schema.@entries`) | — | The strings live next to the schema specs they describe; `SiteForm.render_row/4` reads them via `fetch_spec/1`. |
| `1-N Jump` advertising | Each screen's command-bar builder | Each screen's `tab_labels/1` | Each tabbed screen owns its own command bar; only the literal computation is shared (small helper). |

## Standard Stack

This phase introduces no new libraries. Every dependency below is already
on the project's `mix.lock` and is exercised by the modules Phase 29 modifies.

### Core (already in use)
| Module | Purpose | Why Standard |
|--------|---------|--------------|
| `Foglet.TUI.Command.task/2` (`command.ex:23-38`) | The only sanctioned wrapper around `Raxol.Core.Runtime.Command.task/1` for Foglet TUI. Catches exceptions and emits `{:task_error, op, reason}`. | App-side load operations already use it (boards, oneliners, moderation). Required by AGENTS.md and CONTEXT.md D-04. |
| `Foglet.TUI.App.do_update/2` | Dispatch+result router used by every async TUI load. Has a `{:command_result, inner}` re-entry point at `app.ex:917-923` that re-dispatches Raxol-wrapped task returns. | Existing pattern — Moderation, oneliners, boards, threads, posts all flow through it. |
| `Foglet.TUI.App.process_screen_commands/2` (`app.ex:1340-1359`) | Auto-router that forwards atom-keyed tuples returned by a screen's `handle_key/2` into `do_update/2`. | No screen-side change needed beyond emitting the new tuple shapes; the existing router handles them. |
| `Foglet.Config.Schema.fetch_spec/1` | Authoritative read for field label/description/enum/min/max. | SiteForm's per-render Modal.Form construction already uses it. Description rewrites land in the `@entries` literal in `schema.ex:49-125`. |
| `Foglet.Accounts.transition_user_status/3` (`accounts.ex:249-274`) | Authoritative writer for status transitions. Re-checks `permit_status_transition/2` server-side. | Unchanged in Phase 29; UsersView's existing call site is preserved. |
| `Foglet.Accounts.list_user_status_admin_targets/1` (`accounts.ex:286+`) | Returns `{:ok, %{pending: [...], active: [...], ...}}` or `{:error, :forbidden}`. The `:forbidden` shape is exactly the `{:error, :forbidden}` Phase 29 surfaces in the dedicated panel. | Already returns `:forbidden`; no boundary change. |
| `Foglet.TUI.Widgets.Modal.Form.set_submit_state/2` | Public submit-state setter. Phase 28 D-03/D-08 already lands `:saved` for one render cycle. | `SiteForm.persist_payload/3` (`site_form.ex:198-200`) already calls `set_submit_state(form, :saved)`. Phase 29 D-19 acceptance ("Saved." substring) is satisfied as long as Phase 28 ships. |
| `Foglet.TUI.Theme` (slots `selected.fg`, `selected.bg`, `dim.fg`, `error.fg`, `warning.fg`, `accent.fg`, `primary.fg`) | Theme-routed color slots. | Already used by `users_view.ex:131-135` for selection. Phase 29 D-24 reuses the same slots on INVITES. |
| `Raxol.Core.Renderer.View` (imported as `text`, `column`, etc.) | Render primitive. | Used everywhere in the TUI tree. |

### Supporting (already in use)
| Module | Purpose | When to Use |
|--------|---------|-------------|
| `Foglet.TUI.Widgets.Display.ConsoleTable` | Table render with selection support. Already used by INVITES at `invites_surface.ex:83`. | Used in the live `InvitesState`-backed render path. |
| `Foglet.TUI.Widgets.List.SelectionList` + `ListRow` | Legacy raw-map invites render path. | Plan-phase audits whether the focus highlight is visibly distinct here at 80×24 and may need cell wrapping per CONTEXT.md D-24. |
| `Foglet.TUI.Widgets.Chrome.ScreenFrame` | Outer frame + breadcrumb + command bar plumbing. | Already used by Sysop, Account, Moderation. Renders the command bar from a list of `%{label, commands: [%{key, label, priority}]}` groups. |

### Alternatives Considered (and rejected per CONTEXT.md)
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Bare tagged enum (`:not_loaded | :loading | {:loaded, _} | {:error, _}`) | `%Foglet.TUI.Screens.Sysop.Lifecycle{}` envelope struct with `state`, `loaded_at`, `retry_count` fields | Rejected per CONTEXT.md D-07 ("Considered and explicitly rejected" in `<deferred>`). Re-evaluate only if retry telemetry, staleness tracking, or last-loaded-at metadata becomes load-bearing. The bare tagged enum is sufficient and matches the SPEC type literal. |
| `valid_status_transitions/1` in `Foglet.Accounts` | Mirror the four clauses inside `UsersView` | Rejected per CONTEXT.md D-14. Mirroring lets the rules drift; placing the predicate next to its writer guarantees a single source of truth. |
| Global `[R] Retry` advertising | Active-tab-only retry advertising | Rejected per CONTEXT.md D-13. Active-tab-only is a deliberate UX choice — a global retry would let an operator press R while viewing a healthy SITE and silently reload BOARDS. |
| New theme slots for INVITES focus | Reuse `theme.selected.fg`/`bg` | Rejected per CONTEXT.md D-24. UsersView already proves these slots render visibly at 80×24. |

**Installation:** None. No new packages.

**Version verification:** Not applicable — no third-party packages added.

## Architecture Patterns

### System Architecture Diagram

```
                          USER PRESSES TAB / NAVIGATES TO :sysop
                                          |
                                          v
        +-----------------------------------------------------------+
        |                Foglet.TUI.Screens.Sysop                   |
        |  handle_key/2 -> Tabs.handle_event/2 -> {:tab_changed, i} |
        |                                                            |
        |  if active_tab slot == :not_loaded:                        |
        |     transition slot -> :loading                            |
        |     append {:load_sysop_<tab>} to commands list            |
        |  return {:update, new_state, commands}                     |
        +-----------------------------------------------------------+
                                          |
                                          | commands list
                                          v
        +-----------------------------------------------------------+
        |        Foglet.TUI.App.process_screen_commands/2           |
        |             (app.ex:1340-1359 — UNCHANGED)                |
        |   for each atom-keyed tuple: do_update(tuple, acc_state)  |
        +-----------------------------------------------------------+
                                          |
                                          v
        +-----------------------------------------------------------+
        |   Foglet.TUI.App.do_update({:load_sysop_users}, state)    |
        |     (NEW; modeled on app.ex:513-525 moderation triad)     |
        |   1. domain_module(state, :accounts)                       |
        |   2. put_sysop_loading(state, :users) -> state'            |
        |   3. Foglet.TUI.Command.task(:load_sysop_users, fn ->      |
        |        {:sysop_users_loaded,                               |
        |         accounts_mod.list_user_status_admin_targets(user)} |
        |      end)                                                  |
        |   return {state', [task]}                                  |
        +-----------------------------------------------------------+
                                          |
                                          | (Raxol runtime; async)
                                          v
        +-----------------------------------------------------------+
        |   {:command_result, {:sysop_users_loaded, result}}        |
        |     (Raxol wraps every task return in :command_result —   |
        |      app.ex:917-923 re-enters do_update/2)                |
        +-----------------------------------------------------------+
                                          |
                              +-----------+-----------+
                              |                       |
                  result: {:ok, payload}      result: {:error, reason}
                              |                       |
                              v                       v
              +------------------------+   +-------------------------+
              | put_sysop_loaded(      |   | put_sysop_error(        |
              |   state, :users,       |   |   state, :users,        |
              |   UsersView struct)    |   |   reason)               |
              |  -> slot transitions   |   |  -> slot transitions    |
              |     to {:loaded, _}    |   |     to {:error, reason} |
              +------------------------+   +-------------------------+
                              |                       |
                              +-----------+-----------+
                                          |
                                          v
        +-----------------------------------------------------------+
        |          Sysop.render_tab_body/3 PATTERN-MATCHES          |
        |                                                            |
        |   :not_loaded     -> brief "Loading…" (transition cycle)  |
        |   :loading        -> "Loading…" (theme.dim.fg)            |
        |   {:loaded, sub}  -> <SubModule>.render(sub, theme)       |
        |   {:error, :forbidden}                                    |
        |                   -> "Insufficient role to view this tab."|
        |                      (theme.warning.fg)                   |
        |                      [R] Retry SUPPRESSED                 |
        |   {:error, _other}                                        |
        |                   -> "Could not load <tab>. Press R..."   |
        |                      (theme.error.fg)                     |
        |                      [R] Retry advertised in command bar  |
        +-----------------------------------------------------------+
```

### Recommended Project Structure (additive only)

```
lib/foglet_bbs/
├── accounts.ex                        # +valid_status_transitions/1 public function
├── config/
│   └── schema.ex                      # rewrite 5 description strings in @entries
└── tui/
    ├── app.ex                         # +4 load clauses, +4 result clauses, +put_sysop_* helpers
    └── screens/
        ├── account.ex                 # @key_bar -> render-time builder, insert {"1-N", "Jump"} group
        ├── moderation.ex              # @key_list -> render-time builder, replace "1-6" with "1-N"
        └── sysop/
            ├── sysop.ex               # render_tab_body/3 pattern-match, delegate_to_submodule guard, jump_hint refactor, retry handler, [X] Revoke wiring
            ├── state.ex               # 4 slot defaults: nil -> :not_loaded; tagged enum typespec
            └── users_view.ex          # @footer -> render-time function; error_message/3 (handle, from, to)

test/foglet_bbs/
├── accounts_test.exs                  # +valid_status_transitions/1 unit tests
└── tui/
    ├── layout_smoke_test.exs          # +1-N Jump assertions across Account/Moderation/Sysop @ 64x22 + 80x24
    └── screens/
        ├── sysop_test.exs             # +tab-switch auto-load, retry round-trip, forbidden panel, USERS gating, USERS from->to copy
        ├── shared/
        │   └── invites_surface_test.exs  # +focus highlight at 80x24
        └── sysop/
            └── (no new files; sysop_test.exs covers UsersView changes inline)
```

### Pattern 1: Tagged-Enum Lifecycle Slot

**What:** Each of `:boards_view`, `:limits_form`, `:system_snapshot`, `:users_view` in `Foglet.TUI.Screens.Sysop.State` holds a value matching the type:

```elixir
@type lifecycle(struct_t) ::
        :not_loaded
        | :loading
        | {:loaded, struct_t}
        | {:error, atom()}
```

**When to use:** Any tab body that requires async data load and must distinguish "we haven't tried yet" from "we tried and it failed" from "we have data."

**Example:**
```elixir
# state.ex (rewritten)
defstruct [
  :tabs,
  active_tab: 0,
  tab_labels: @base_tabs,
  invites: InvitesState.new(),
  site_form: nil,                  # SITE stays sync per D-03 — no tagged enum
  limits_form: :not_loaded,        # was: nil
  boards_view: :not_loaded,        # was: nil
  system_snapshot: :not_loaded,    # was: nil
  users_view: :not_loaded          # was: nil
]
```

```elixir
# sysop.ex render_tab_body/3 (rewritten)
defp render_tab_body("USERS", ss, theme) do
  case ss.users_view do
    :not_loaded -> loading_panel(theme)            # transient; only visible during dispatch cycle
    :loading -> loading_panel(theme)
    {:loaded, sub} -> UsersView.render(sub, theme)
    {:error, :forbidden} -> forbidden_panel("users", theme)
    {:error, _reason} -> error_panel("users", theme)
  end
end

defp loading_panel(theme),
  do: column(style: %{gap: 0}, do: [text("Loading…", fg: theme.dim.fg)])

defp forbidden_panel(_tab, theme),
  do: column(style: %{gap: 0}, do: [text("Insufficient role to view this tab.", fg: theme.warning.fg)])

defp error_panel(tab, theme),
  do: column(style: %{gap: 0}, do: [text("Could not load #{tab}. Press R to retry.", fg: theme.error.fg)])
```

### Pattern 2: App-Level Load Triad (mirror Moderation verbatim)

**What:** Every async load follows three-step shape: dispatch clause → result clause(s) → `put_*` helpers.

**When to use:** Any TUI load that calls a domain boundary asynchronously through `Foglet.TUI.Command.task/2`.

**Example (modeled on `app.ex:513-533, 1079-1114`):**
```elixir
# NEW load clause (paste 4×, one per tab)
defp do_update({:load_sysop_users}, state) do
  user = state.current_user
  accounts_mod = domain_module(state, :accounts)

  state = put_sysop_loading(state, :users_view)

  task =
    Foglet.TUI.Command.task(:load_sysop_users, fn ->
      result =
        case accounts_mod.list_user_status_admin_targets(user) do
          {:ok, groups} -> {:ok, UsersView.from_groups(groups, user)}
          {:error, reason} -> {:error, reason}
        end

      {:sysop_users_loaded, result}
    end)

  {state, [task]}
end

# NEW result clauses (paste 4×, one per tab)
defp do_update({:sysop_users_loaded, {:ok, sub}}, state),
  do: {put_sysop_loaded(state, :users_view, sub), []}

defp do_update({:sysop_users_loaded, {:error, reason}}, state),
  do: {put_sysop_error(state, :users_view, reason), []}

# NEW helpers (3 helpers; each takes the slot atom)
defp put_sysop_loading(state, slot),
  do: update_sysop_slot(state, slot, :loading)

defp put_sysop_loaded(state, slot, sub),
  do: update_sysop_slot(state, slot, {:loaded, sub})

defp put_sysop_error(state, slot, reason),
  do: update_sysop_slot(state, slot, {:error, reason})

defp update_sysop_slot(state, slot, new_value) do
  ss =
    state.screen_state
    |> Map.get(:sysop) ||
      Foglet.TUI.Screens.Sysop.init_screen_state(current_user: state.current_user, session_context: state.session_context)
  ss = Map.put(ss, slot, new_value)
  %{state | screen_state: Map.put(state.screen_state || %{}, :sysop, ss)}
end
```

### Pattern 3: Tab-Switch Dispatch Site

**What:** When `Tabs.handle_event/2` reports `{:tab_changed, idx}`, check the new active tab's slot. If `:not_loaded`, transition to `:loading` AND emit a dispatch tuple in the same `commands` return list.

**Where:** `sysop.ex:170-192` `handle_key/2` (the existing tab-changed branch).

**Example:**
```elixir
def handle_key(event, state) do
  ss = get_screen_state(state)
  {new_tabs, action} = Tabs.handle_event(event, ss.tabs)

  if action == nil and new_tabs == ss.tabs do
    delegate_to_active_tab(event, state, ss)
  else
    new_active =
      case action do
        {:tab_changed, idx} -> idx
        _ -> ss.active_tab
      end

    new_ss =
      ss
      |> Map.merge(%{tabs: new_tabs, active_tab: new_active})
      |> maybe_load_invites_on_entry(state)

    # NEW: compute dispatch BEFORE freezing screen_state, so the slot is
    # visibly :loading on the next render even if dispatch is a no-op
    # (e.g. tab already :loaded).
    {new_ss, commands} = maybe_dispatch_lifecycle_load(new_ss, new_active)

    new_screen_state = Map.put(state.screen_state, :sysop, new_ss)
    {:update, %{state | screen_state: new_screen_state}, commands}
  end
end

defp maybe_dispatch_lifecycle_load(ss, active_idx) do
  case Enum.at(State.tab_labels(ss), active_idx) do
    "BOARDS" -> dispatch_if_not_loaded(ss, :boards_view, {:load_sysop_boards})
    "LIMITS" -> dispatch_if_not_loaded(ss, :limits_form, {:load_sysop_limits})
    "SYSTEM" -> dispatch_if_not_loaded(ss, :system_snapshot, {:load_sysop_system})
    "USERS"  -> dispatch_if_not_loaded(ss, :users_view, {:load_sysop_users})
    _ -> {ss, []}    # SITE / INVITES handled separately
  end
end

defp dispatch_if_not_loaded(ss, slot, dispatch_tuple) do
  case Map.get(ss, slot) do
    :not_loaded -> {Map.put(ss, slot, :loading), [dispatch_tuple]}
    _ -> {ss, []}
  end
end
```

### Pattern 4: First-Entry Auto-Load

**What:** When the user navigates to `:sysop` (e.g. from the main menu), the active tab — typically SITE (idx 0) — is sync. But the SPEC requires that *if* the operator's last-active tab was a lifecycle tab (or if SYSOP defaults change), entry triggers a dispatch.

**Recommended insertion point:** Extend `App.do_update({:navigate, :sysop}, state)` analogously to how `:moderation` is handled at `app.ex:321-322`:

```elixir
defp do_update({:navigate, screen}, state) when is_atom(screen) do
  new_state = %{state | current_screen: screen, modal: nil}

  cond do
    screen == :main_menu and new_state.current_user ->
      do_update({:load_oneliners}, new_state)

    screen == :moderation and new_state.current_user ->
      do_update({:load_moderation_workspace}, new_state)

    screen == :sysop and new_state.current_user ->
      maybe_dispatch_initial_sysop_load(new_state)    # NEW

    true ->
      {new_state, []}
  end
end

defp maybe_dispatch_initial_sysop_load(state) do
  ss = state.screen_state[:sysop] || Sysop.init_screen_state(current_user: state.current_user)
  active_label = Enum.at(SysopState.tab_labels(ss), ss.active_tab)

  case active_label do
    "BOARDS" -> do_update({:load_sysop_boards}, state)
    "LIMITS" -> do_update({:load_sysop_limits}, state)
    "SYSTEM" -> do_update({:load_sysop_system}, state)
    "USERS"  -> do_update({:load_sysop_users}, state)
    _ -> {state, []}    # SITE (default) and INVITES are sync
  end
end
```

**Idempotency:** `dispatch_if_not_loaded/3` (Pattern 3) gates on `:not_loaded`, so re-entering Sysop while a tab is already `{:loaded, _}` emits no command. CONTEXT.md D-06 satisfied.

### Pattern 5: USERS Render-Time Footer + Keybind Gating

**What:** Replace the static `@footer` module attribute at `users_view.ex:23, 100` with a render-time function that consults `Foglet.Accounts.valid_status_transitions/1` for the focused row's status. Add per-key guards in `handle_key/2` that no-op disallowed transitions.

**Example:**
```elixir
# users_view.ex (rewritten)
defp footer_text(%__MODULE__{rows: []}), do: "[j/k] Move"

defp footer_text(%__MODULE__{rows: rows, selection_index: idx}) do
  {focused_status, _user} = Enum.at(rows, idx)
  allowed = Accounts.valid_status_transitions(focused_status)

  parts =
    [
      if(:active in allowed and focused_status == :pending, do: "[A] Approve"),
      if(:rejected in allowed, do: "[R] Reject"),
      if(:suspended in allowed, do: "[S] Suspend"),
      if(:active in allowed and focused_status in [:suspended], do: "[U] Reactivate"),
      "[j/k] Move"
    ]
    |> Enum.reject(&is_nil/1)

  Enum.join(parts, "  ")
end

# Replace the four char-key clauses with guard-bearing versions:
def handle_key(%{key: :char, char: c}, state) when c in ["A", "a"],
  do: maybe_transition(state, :active, allowed_targets(state))

defp maybe_transition(state, target, allowed) do
  if target in allowed, do: transition(state, target), else: {state, []}
end

defp allowed_targets(%__MODULE__{rows: []}), do: []
defp allowed_targets(%__MODULE__{rows: rows, selection_index: idx}) do
  {status, _user} = Enum.at(rows, idx)
  Accounts.valid_status_transitions(status)
end
```

**Key insight:** The CONTEXT.md D-15 spec for which keys map to which target statuses must distinguish:
- `[A] Approve` → `:active` from `:pending` only
- `[R] Reject` → `:rejected` from `:pending` only
- `[S] Suspend` → `:suspended` from `:active` only
- `[U] Reactivate` → `:active` from `:suspended` only

The current code in `users_view.ex:66-77` collapses `[A]` and `[U]` to the same `:active` target, which is wrong because `[A]` should be hidden on a focused `:suspended` row (use `[U]` instead) and `[U]` should be hidden on a focused `:pending` row (use `[A]` instead). Plan-phase must distinguish these. **Confirm with discuss-phase if unclear** — CONTEXT.md D-15 says "Only keybinds whose target status is in the allowed set are advertised" but the rule for choosing between `A` vs `U` (both target `:active`) is not made explicit.

### Pattern 6: From→To Error Copy Builder

**What:** Replace `error_message(:invalid_transition)` with a function that takes handle, from-status, to-status and emits user-facing copy.

**Example:**
```elixir
# Before (users_view.ex:213):
defp error_message(:invalid_transition), do: "Invalid status transition."

# After:
defp invalid_transition_message(handle, from, to),
  do: "Cannot change @#{handle} from #{to_string(from)} to #{to_string(to)}."

# Updated call site (users_view.ex:200 transition/2 error branch):
{:error, :invalid_transition} ->
  {_status, focused_user} = Enum.at(state.rows, state.selection_index)
  msg = invalid_transition_message(focused_user.handle, focused_user.status, target_status)
  {%{state | message: msg}, []}
```

**Format mirror:** matches existing success-message format at `users_view.ex:204-208`:
> `"Status changed: @alice pending -> active."`
versus the new error:
> `"Cannot change @alice from active to pending."`

### Pattern 7: Render-Time `1-N Jump` Builder

**What:** Convert two module attributes (`Account.@key_bar`, `Moderation.@key_list`) into render-time functions and add a small helper.

**Example:**
```elixir
# Shared idiom (no shared module needed — small enough to inline per screen,
# but a helper at Foglet.TUI.Widgets.Chrome.KeyBar.jump_hint/1 would be DRY):

defp jump_hint(tab_count) when is_integer(tab_count) and tab_count > 0,
  do: "1-#{tab_count}"

# moderation.ex:44 (rewritten)
# Before:  @key_list [{"←/→", "Tab"}, {"1-6", "Jump"}, {"Q", "Back"}]
# After:   defp key_list(ss), do: [{"←/→", "Tab"}, {jump_hint(length(tab_labels(ss))), "Jump"}, {"Q", "Back"}]
# Call site app.ex:126 ScreenFrame.render(state, ..., @key_list)
#   becomes ScreenFrame.render(state, ..., key_list(ss))

# account.ex:42-48 (rewritten)
# Before:
#   @key_bar [{"←/→", "Tab"}, {"Tab", "Field"}, {"Enter", "Save"}, {"Esc", "Cancel"}, {"Ctrl+Q", "Back"}]
# After:
#   defp key_bar(ss),
#     do: [
#       {"←/→", "Tab"},
#       {jump_hint(length(tab_labels(ss))), "Jump"},
#       {"Tab", "Field"},
#       {"Enter", "Save"},
#       {"Esc", "Cancel"},
#       {"Ctrl+Q", "Back"}
#     ]

# sysop.ex:61 (rewritten)
# Before:  jump_hint = if "INVITES" in State.tab_labels(ss), do: "1-6", else: "1-5"
# After:   jump_hint = "1-#{length(State.tab_labels(ss))}"
```

**Output substring:** Each rendered command-bar group emits `"1-N Jump"` or `"1-N"` + `"Jump"` depending on the screen's chrome formatting. CONTEXT.md D-27 demands the substring `"1-N"` exists in output (where N is the rendered tab count). Verify in tests by collecting text values via `Foglet.TUI.RenderHelpers.collect_text_values/1` and asserting `Enum.any?(values, fn v -> String.contains?(v, "1-3") end)` for an INVITES-hidden Account context (Account base = 3 tabs: PROFILE, PREFS, SSH KEYS).

### Anti-Patterns to Avoid

- **Calling `Raxol.Core.Runtime.Command.task/1` directly from a Sysop module:** forbidden by CONTEXT.md D-04 + grep test. The wrapper exists specifically so `{:task_error, op, reason}` propagation stays uniform.
- **Letting `nil` reach `render_tab_body/3`:** by CONTEXT.md D-10, `nil` is a state-construction error, not a render state. Flip slot defaults from `nil` → `:not_loaded` in `state.ex:39-43` AT THE SAME TIME you rewrite `render_tab_body/3`.
- **Refreshing tab labels in a module attribute:** `@key_bar` and `@key_list` are compile-time frozen and cannot consult runtime tab counts. CONTEXT.md D-26 forces the render-time-function refactor.
- **"Press any key to load" placeholders:** all five literal strings (`sysop.ex:122, 129, 136, 143, 150`) must be removed. SPEC §SYSOP-01 acceptance has a grep test for the substring `"Press any key"`.
- **Submodule events firing on non-loaded slots:** `delegate_to_submodule/5` at `sysop.ex:234-238` today initializes `sub = Map.get(ss, field) || module.init(...)`. CONTEXT.md D-09 forbids this — replace the `||` fallback with a `{:loaded, sub}` pattern match; everything else is a no-op (`:no_match` return).
- **Schema description mentioning `(D-...)` / `REQ-...` / `Phase ...` / `deliverable`:** the grep test in CONTEXT.md D-22 is case-insensitive. The proposed rewrite for `delivery_mode` (`"Whether outbound email is sent."`) must avoid `"deliverable"` — just don't use that word.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Async task wrapping | `Raxol.Core.Runtime.Command.task(fn -> ... end)` directly | `Foglet.TUI.Command.task(:op_atom, fn -> ... end)` | Catches exceptions and emits `{:task_error, op, reason}` so the TUI doesn't lock on "Loading…" forever (`command.ex:9-13` docstring). |
| Tagged-enum lifecycle envelope | A `%Lifecycle{state: :loading, loaded_at: ..., retry_count: ...}` struct | Bare tagged values | CONTEXT.md D-07 explicitly rejects the envelope. The existing submodule struct (`%UsersView{}`, etc.) IS the loaded payload — no envelope needed. |
| Status-transition predicate | A copy of the four `permit_status_transition/2` clauses inside `UsersView` | `Foglet.Accounts.valid_status_transitions/1` (NEW public function derived from the existing private clauses) | AGENTS.md: "domain truth lives in `Foglet.*`." Mirroring lets the rules drift. |
| Saved confirmation row | A new `:saved_message` field on SiteForm.State + a render-time row | Phase 28 D-08's `Saved.` row, already emitted by Modal.Form when `submit_state == :saved` | `SiteForm.persist_payload/3` already calls `set_submit_state(form, :saved)` (`site_form.ex:198-199`). No new code in Phase 29 — only an acceptance test that the substring `"Saved."` appears. |
| Esc discard status row | A `:cancelled_message` row on SiteForm | Phase 28 D-12's no-flash contract — `on_cancel` reseeds drafts; field reversion IS the visible signal | CONTEXT.md D-20/D-21 amends SPEC SYSOP-03 to drop the discard-row criterion. |
| INVITES focus highlight theme slots | New `theme.invites_focus.fg/bg` | `theme.selected.fg`/`theme.selected.bg` (already in use at `users_view.ex:131-135`) | CONTEXT.md D-24. |
| Modal.Form footer disabling | A new `:hide_footer` Sysop-side flag | Phase 28's `:show_footer` init option (default `false`) | Already shipped in Phase 28 D-06. |

**Key insight:** Phase 29 is about *removing* hand-rolled placeholder gating ("Press any key to load") and replacing it with the existing async load triad. The temptation is to build a new lifecycle envelope or a new theme system; resist. Every needed primitive is already in the tree.

## Runtime State Inventory

> Phase 29 has no rename/refactor/string-replacement scope, so this inventory is light. The only "stored data" change is a function name addition; no key/collection renames.

| Category | Items Found | Action Required |
|----------|-------------|-------------------|
| Stored data | None — Phase 29 changes no DB columns, no Ecto schemas, no migrations. The four lifecycle slots live only in `state.screen_state[:sysop]` (in-memory, per-session). | None |
| Live service config | None — no n8n / Datadog / Tailscale / Cloudflare integrations are touched. | None |
| OS-registered state | None — no Task Scheduler / launchd / systemd / pm2 entries reference any string Phase 29 changes. | None |
| Secrets/env vars | None — no env-var name changes; no SOPS keys touched. | None |
| Build artifacts | None — no Mix package renames, no compiled-artifact keys. The `Foglet.Accounts.valid_status_transitions/1` function is added (pure additive); no recompiled-and-still-cached situation. | None |

**Nothing found in any category** — verified by reading CONTEXT.md scope and confirming no decision touches stored state, service config, OS registrations, secrets, or build artifacts. Phase 29 is purely in-process module changes.

## Common Pitfalls

### Pitfall 1: "Press any key" race after `:not_loaded` → `:loading` transition
**What goes wrong:** If the dispatch tuple is appended to `commands` but the slot transition to `:loading` happens on a *different* return cycle, the very first render after tab-switch shows the `:not_loaded` "Loading…" panel briefly. If `delegate_to_submodule/5` (line 234-238) still uses its `Map.get(ss, field) || module.init(...)` fallback, a stray keystroke during the dispatch window can re-init a fresh struct — overwriting the `:loading` tag with a synchronously-initialized struct. The resulting state is incoherent.
**Why it happens:** Today's `delegate_to_submodule/5` lazily initializes any `nil` slot. With tagged enum slots, only `{:loaded, sub}` should reach the submodule's `handle_key/2`.
**How to avoid:** CONTEXT.md D-09 — rewrite `delegate_to_submodule/5` to require `{:loaded, sub}`. On `:loading` / `{:error, _}` / `:not_loaded`, return `:no_match`.
**Warning signs:** Any test that asserts a submodule render (`UsersView.render`) without first injecting `{:loaded, _}` will pass under the old fallback and fail under the new contract — verify by deliberately failing the test first.

### Pitfall 2: Stale `{:loaded, _}` after re-entry
**What goes wrong:** The operator visits Sysop → USERS, the data loads, they switch back to SITE, then return to USERS later. The slot is still `{:loaded, _stale_users}` even though data may have changed.
**Why it happens:** CONTEXT.md D-06 explicitly accepts staleness on re-entry — only `:not_loaded` triggers a dispatch.
**How to avoid:** This is documented behavior, not a bug. If staleness becomes load-bearing, add a manual `[R] Refresh` command (separate from `[R] Retry` on errors). Phase 29 does not include refresh.
**Warning signs:** User confusion. v1.4 deferred `SYSOP-FUT-01: Background prefetch of next/previous Sysop tab` to a later milestone; document staleness in the Phase 29 SUMMARY.

### Pitfall 3: `{:error, :forbidden}` confused with generic load error
**What goes wrong:** If `render_tab_body/3` matches `{:error, _reason}` before `{:error, :forbidden}` (or uses an `_other` catch-all in the wrong order), the forbidden case gets the generic copy with `[R] Retry` advertised — and pressing R just dispatches another `:forbidden` result, looking broken.
**Why it happens:** Pattern-match order in Elixir.
**How to avoid:** In `render_tab_body/3` (and in any retry-advertising code), match `{:error, :forbidden}` BEFORE `{:error, _other}`. Same in the command-bar builder — gate `[R] Retry` advertising on `match?({:error, reason}, slot) and reason != :forbidden`.
**Warning signs:** A render test that asserts `"[R] Retry"` is *absent* under `{:error, :forbidden}` will catch this immediately. CONTEXT.md D-13 + SPEC §SYSOP-02 acceptance both require this assertion.

### Pitfall 4: Module attribute compile-time freeze
**What goes wrong:** `@key_bar` / `@key_list` are evaluated at compile time and frozen as immutable terms. They cannot reference runtime values like `length(tab_labels(state))`.
**Why it happens:** Elixir module attributes used as values (not pre-compile config) are constants.
**How to avoid:** CONTEXT.md D-26 — convert to render-time functions. The cost is one function per screen; the win is correct `1-N` regardless of INVITES visibility.
**Warning signs:** A test that runs Account/Moderation/Sysop with INVITES visible and INVITES hidden, asserting the `1-N` literal differs in the rendered text, will catch any module-attribute residue.

### Pitfall 5: SPEC SYSOP-03 vs Phase 28 D-12 conflict (Esc discard row)
**What goes wrong:** SPEC SYSOP-03 acceptance reads "the next render contains a discard status row." Phase 28 D-10/D-12 explicitly drops the discard row in favor of field-value reversion. A literal-string test of "draft discarded" or similar will fail.
**Why it happens:** SPEC was authored before the Phase 28 honest-Esc decision was locked.
**How to avoid:** CONTEXT.md D-20/D-21 amends SPEC SYSOP-03 to: (a) After Esc, rendered draft equals saved Config value. (b) After Esc, rendered field values reflect the saved value (no draft echo). (c) Esc does not navigate away. The "discard status row" criterion is dropped.
**Warning signs:** Any test that searches for `"Changes discarded"` or `"draft discarded"` should be removed/rewritten before plan execution.

### Pitfall 6: Schema description grep regex case-insensitive
**What goes wrong:** The grep test in CONTEXT.md D-22 is case-insensitive: `(D-\d+|REQ-[A-Z]+-\d+|Phase \d+|Pitfall \d+|deliverable)/i`. A rewritten description like `"Whether outbound mail is delivered."` would match `"delivered"` → `deliverable`? No — `delivered` is fine; only the word `deliverable` matches. But `"Per-phase config..."` would match `Phase`. Watch for incidental matches.
**Why it happens:** The regex's word matches don't include word boundaries, but only the listed substrings (`D-` followed by digits, `REQ-` etc.) need exact prefixes. `deliverable` is a literal substring match.
**How to avoid:** Use the proposed CONTEXT.md D-23 strings verbatim or close paraphrases. Run the grep locally before merging plan deliverables.
**Warning signs:** A test in `test/foglet_bbs/config/schema_test.exs` (or a new test file) iterating `Schema.entries()` and applying the regex catches every description automatically.

### Pitfall 7: ConsoleTable selection invisibility in INVITES
**What goes wrong:** `ConsoleTable.render/2` may not visibly highlight the selected row at 80×24 SSH (depending on the widget's selection rendering). UsersView at `users_view.ex:131-135` works around this by NOT using ConsoleTable for row content — it renders bespoke text rows wrapped in `text(label, fg: theme.selected.fg, bg: theme.selected.bg)`.
**Why it happens:** ConsoleTable's selection styling may rely on cursor positioning that doesn't survive layout-engine flattening.
**How to avoid:** CONTEXT.md D-24 — plan-phase audits whether ConsoleTable selection is visibly distinct at 80×24. If not, wrap the focused row's cells in the legacy raw-map render path (`invites_surface.ex:112-118`) with `text(..., fg: theme.selected.fg, bg: theme.selected.bg)` — the same idiom UsersView uses.
**Warning signs:** A render-smoke test at 80×24 with three invites where row 2 is focused, asserting the rendered tokens for row 2 differ from rows 1 and 3, catches this before merge.

### Pitfall 8: Closure capture of `state.current_user` in load tasks
**What goes wrong:** If the load closure captures `state` directly, every reference to `state.current_user` re-binds `state`. If the user logs out between dispatch and result, the result handler may operate on a stale state. More commonly: the test override `domain_module(state, :accounts)` must be evaluated at dispatch time, not at task-execution time.
**Why it happens:** Elixir closures capture by reference. The Moderation precedent at `app.ex:514-525` evaluates `user = state.current_user` and `moderation_mod = domain_module(state, :moderation)` BEFORE building the task closure — closing over the values, not the state.
**How to avoid:** Mirror the Moderation pattern verbatim. Bind `user` and `accounts_mod` (etc.) outside the `Foglet.TUI.Command.task/2` block, then reference those bindings inside the closure.
**Warning signs:** Tests that swap `domain_module/2` via `Foglet.TUI.Domain.put/3` (the test override hook) will fail intermittently if the closure captures `state` by reference instead of the bound value.

## Code Examples

### Adding `valid_status_transitions/1` to `Foglet.Accounts`

```elixir
# accounts.ex — derive from existing permit_status_transition/2 at lines 187-191

@doc """
Returns the list of valid target statuses for `from_status`.

Sourced from the same predicate `transition_user_status/3` enforces
server-side (`permit_status_transition/2`); using this function for
UI-side keybind gating guarantees no drift.

  iex> Foglet.Accounts.valid_status_transitions(:pending)
  [:active, :rejected]

  iex> Foglet.Accounts.valid_status_transitions(:active)
  [:suspended]

  iex> Foglet.Accounts.valid_status_transitions(:suspended)
  [:active]

  iex> Foglet.Accounts.valid_status_transitions(:rejected)
  []
"""
@spec valid_status_transitions(:pending | :active | :suspended | :rejected) ::
        [:active | :suspended | :rejected]
def valid_status_transitions(:pending), do: [:active, :rejected]
def valid_status_transitions(:active), do: [:suspended]
def valid_status_transitions(:suspended), do: [:active]
def valid_status_transitions(:rejected), do: []
```

### Retry Handler in `Sysop.handle_key/2`

```elixir
# sysop.ex — new clause BEFORE the catch-all handle_key/2 at line 170

# CONTEXT.md D-13: [R] Retry only when active tab is in {:error, _} where reason != :forbidden
def handle_key(%{key: :char, char: c}, state) when c in ["r", "R"] do
  ss = get_screen_state(state)
  active_label = Enum.at(State.tab_labels(ss), ss.active_tab)
  slot = slot_for(active_label)
  current = Map.get(ss, slot)

  case current do
    {:error, reason} when reason != :forbidden ->
      new_ss = Map.put(ss, slot, :loading)
      new_screen_state = Map.put(state.screen_state, :sysop, new_ss)
      {:update, %{state | screen_state: new_screen_state}, [dispatch_for(active_label)]}

    _ ->
      :no_match
  end
end

defp slot_for("BOARDS"), do: :boards_view
defp slot_for("LIMITS"), do: :limits_form
defp slot_for("SYSTEM"), do: :system_snapshot
defp slot_for("USERS"), do: :users_view
defp slot_for(_), do: nil

defp dispatch_for("BOARDS"), do: {:load_sysop_boards}
defp dispatch_for("LIMITS"), do: {:load_sysop_limits}
defp dispatch_for("SYSTEM"), do: {:load_sysop_system}
defp dispatch_for("USERS"), do: {:load_sysop_users}
```

### Retry Hint Advertising in `sysop_commands/1`

```elixir
# sysop.ex — rewrite sysop_commands/1 (currently sysop.ex:83-97)

defp sysop_commands(ss, jump_hint) do
  base = [
    %{label: "System", commands: [%{key: "Q", label: "Back", priority: 0}]},
    %{
      label: "Tabs",
      commands: [
        %{key: "←/→", label: "Tab", priority: 10},
        %{key: jump_hint, label: "Jump", priority: 10}
      ]
    }
  ]

  base
  |> maybe_add_retry(ss)
  |> maybe_add_revoke(ss)
end

defp maybe_add_retry(groups, ss) do
  active_label = Enum.at(State.tab_labels(ss), ss.active_tab)

  case Map.get(ss, slot_for(active_label) || :__none__) do
    {:error, reason} when reason != :forbidden ->
      groups ++ [%{label: "Action", commands: [%{key: "R", label: "Retry", priority: 5}]}]

    _ ->
      groups
  end
end

defp maybe_add_revoke(groups, ss) do
  case Enum.at(State.tab_labels(ss), ss.active_tab) do
    "INVITES" ->
      case Foglet.TUI.Screens.Shared.InvitesState.selected_item(ss.invites) do
        %{status: status} when status != :revoked ->
          # CONTEXT.md D-25: only when Enter has been pressed on a focused, non-revoked row.
          # Plan-phase chooses the focused-and-confirmed-Enter signal. One option: store an
          # :armed_revoke? boolean on InvitesState, set by Enter, cleared by selection move.
          if Map.get(ss.invites, :armed_revoke?, false) do
            groups ++ [%{label: "Invite", commands: [%{key: "X", label: "Revoke", priority: 5}]}]
          else
            groups
          end

        _ ->
          groups
      end

    _ ->
      groups
  end
end
```

### Site Schema Description Rewrites (CONTEXT.md D-23 literals)

```elixir
# config/schema.ex — replace description: strings on the 5 @site_keys

# registration_mode (line 54)
description: "How new accounts are created.",

# invite_code_generators (line 63)
description: "Who can generate invite codes.",

# delivery_mode (line 90)
description: "Whether outbound email is sent.",

# require_email_verification (line 99-100)
description: "Require email verification before login.",

# invite_generation_per_user_limit (line 119-120)
description: "Per-user invite cap (0 = unlimited).",
```

### `mix foglet.tui.render` Visual Inspection

```bash
# Inspect Sysop SITE at default 80×24 with seeded sysop fixture (alice)
rtk mix foglet.tui.render sysop

# Smaller viewport
rtk mix foglet.tui.render sysop --width 64 --height 22

# Confirm 1-N Jump on Account / Moderation / Sysop
rtk mix foglet.tui.render account
rtk mix foglet.tui.render moderation
```

`Foglet.TUI.RenderFixtures` (`render_fixtures.ex:240-242`) seeds Sysop with `Sysop.init_screen_state([])` — slots are `nil` today; once Phase 29 flips the defaults to `:not_loaded`, the renderer will display the `Loading…` panel for whichever lifecycle tab the user lands on (until a real load completes; in the visual-inspection harness there is no App update cycle so it stays loading).

For non-sysop forbidden testing, no fixture exists today — plan-phase may need to extend `RenderFixtures` with a `:user`-role variant, or inject `{:error, :forbidden}` directly into `state.screen_state[:sysop].users_view` before calling `Sysop.render/1` in the test (matches the existing harness pattern at `sysop_test.exs:127, 1155, 1171`).

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `term() | nil` slots with `nil`-fallback lazy `init` in `delegate_to_submodule/5` | Tagged enum `:not_loaded | :loading | {:loaded, _} | {:error, _}` with App-side async load | Phase 29 (this phase) | Kills "Press any key to load." |
| Static `@footer = "[A] Approve …"` always-visible | Render-time `footer_text/1` consulting `Foglet.Accounts.valid_status_transitions/1` | Phase 29 | Honest UI: keybinds shown only when they would succeed. |
| `@key_list [{"1-6", "Jump"}, ...]` hardcoded | Render-time `key_list/1` building `{jump_hint(length(tabs)), "Jump"}` | Phase 29 | Correct N regardless of INVITES visibility. |
| SiteForm bespoke "▸ key: value" + description rendering | Modal.Form-backed wrapper with standard render | Phase 28 (already shipped) | Consistent form behavior across Account/Sysop. |
| SiteForm Esc → no-op (or no `:escape` clause) | SiteForm Esc → reseed drafts via `on_cancel` callback (no inline status copy) | Phase 28 (already shipped) | Honest Esc per Phase 28 D-10/D-12. |
| Site description copy with `(D-02/D-03)` planning IDs | User-facing operator copy | Phase 29 | Operators see honest descriptions; SPEC §SYSOP-04 acceptance grep test passes. |

**Deprecated/outdated:**
- The five `placeholder("Press any key to load …", theme)` calls at `sysop.ex:122, 129, 136, 143, 150`. Replace with `loading_panel/forbidden_panel/error_panel` per Pattern 1.
- The static `@footer` string at `users_view.ex:23` and its sole consumer at `users_view.ex:100`. Replace with `footer_text/1`.
- The `invite_key/1` event mapping pattern at `sysop.ex:230-232` is fine as-is — INVITES retains its existing event flow per CONTEXT.md D-03.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | First-entry guard inserted at `App.do_update({:navigate, :sysop}, _)` is the cleanest precedent (mirrors Moderation at `app.ex:321-322`). [ASSUMED] | Pattern 4 | If `Sysop.init_screen_state/1` is invoked from a path other than `{:navigate, :sysop}` (e.g. session restore), the first-entry dispatch would not fire. Audit all `current_screen: :sysop` setters in plan-phase. Mitigation: also call `maybe_dispatch_initial_sysop_load/1` from `Sysop.init/1` if such a path exists. |
| A2 | Rule for choosing between `[A] Approve` (target `:active` from `:pending`) and `[U] Reactivate` (target `:active` from `:suspended`) is: show `[A]` only when focused row is `:pending`; show `[U]` only when focused row is `:suspended`. [ASSUMED] | Pattern 5 | If the rule is "show both when target `:active` is reachable," the keybind set is wrong but the underlying transition still succeeds. CONTEXT.md D-15 doesn't disambiguate. **Confirm with discuss-phase.** |
| A3 | `[X] Revoke` requires "armed" state (Enter pressed on a focused non-revoked row) before being advertised. [ASSUMED] | Pattern in `maybe_add_revoke/2` | CONTEXT.md D-25 says "Pressing Enter on a focused INVITES row whose status is not `:revoked` adds an `[X] Revoke` group." This implies a two-step gesture (Enter → X). If actually meant to advertise `[X]` whenever a non-revoked row is focused (no Enter required), the implementation is simpler. **Confirm with discuss-phase.** |
| A4 | `Foglet.Accounts.list_user_status_admin_targets/1` returns `{:error, :forbidden}` already (matches the `:forbidden` case Phase 29 surfaces). [VERIFIED: accounts.ex:286 boundary, returns `{:error, :forbidden}` from Bodyguard.permit failure] | App-level dispatch | None — verified. |
| A5 | Phase 28's `Saved.` row substring is rendered exactly as `"Saved."` (with trailing period). [VERIFIED: form.ex:405 `render_status_row(state.submit_state, theme)` per Phase 28 D-08, and `site_form.ex:198-199` calls `set_submit_state(form, :saved)` on all-keys-success] | Pitfall section, D-19 | None — verified. |
| A6 | `theme.selected.fg`/`theme.selected.bg` slots exist on the current Theme map. [VERIFIED: `users_view.ex:131-135` already uses both slots; `Foglet.TUI.Theme` exposes them] | Pattern 7 | None — verified. |
| A7 | The grep regex `(D-\d+|REQ-[A-Z]+-\d+|Phase \d+|Pitfall \d+|deliverable)/i` evaluated against the 5 proposed CONTEXT.md D-23 strings yields zero matches. [VERIFIED by manual inspection: "How new accounts are created." / "Who can generate invite codes." / "Whether outbound email is sent." / "Require email verification before login." / "Per-user invite cap (0 = unlimited)." — none contain D-, REQ-, Phase, Pitfall, or deliverable] | Pitfall 6 | None — verified. |
| A8 | `process_screen_commands/2` re-dispatches the four new `{:load_sysop_*}` tuples without code change. [VERIFIED: `app.ex:1349-1351` matches any tuple where `is_atom(elem(tuple, 0))` and routes to `do_update/2`] | Pattern 2 | None — verified. |

**The four `{:load_sysop_*}` and four `{:sysop_*_loaded, _}` tuple shapes need to be added as `do_update/2` clauses in `app.ex` to match. The screen-side router does not need extension.**

## Open Questions

1. **First-entry default tab is SITE — does Phase 29 also need a default-active-tab change?**
   - What we know: `Foglet.TUI.Screens.Sysop.State.new/1` defaults `active: 0` (i.e. SITE). SITE is sync, so first-entry dispatches no command in the common case.
   - What's unclear: If a future change makes a lifecycle tab the default landing, the first-entry dispatch must fire. Pattern 4 covers this — `maybe_dispatch_initial_sysop_load/1` checks the current active tab dynamically.
   - Recommendation: Implement Pattern 4 even though it's a no-op today on the SITE default; the cost is one `case` statement and the win is correctness when active-tab persistence is added later.

2. **Does `Foglet.TUI.App` have a `domain_module(state, :accounts)` lookup, or is `Foglet.Accounts` referenced directly?**
   - What we know: `app.ex:991` shows `default_domain_module/1` clauses for `:boards`, `:threads`, `:posts`, `:oneliners`, `:moderation`. Accounts is not currently aliased through this mechanism.
   - What's unclear: For test-injectability of `Accounts.list_user_status_admin_targets/1` and `Accounts.valid_status_transitions/1`, plan-phase may want to add `:accounts` to the domain map.
   - Recommendation: Skip the test override for now; sysop tests today inject directly into `state.screen_state[:sysop]` (see `sysop_test.exs:1155, 1171, 1456, 1469`) without going through the domain hook. Either approach is consistent with existing patterns; plan-phase chooses.

3. **Are there other call sites for `permit_status_transition/2` that should also consume `valid_status_transitions/1`?**
   - What we know: Today `permit_status_transition/2` is private and called only from `transition_user_status/3` at `accounts.ex:255`.
   - What's unclear: Probably not — it's only used at the writer boundary. But verify by `grep -rn permit_status_transition lib/` before plan-phase.
   - Recommendation: Keep `permit_status_transition/2` private; add `valid_status_transitions/1` as a sibling public function. Both encode the same rules; the writer keeps using the existing private guard for symmetry, while UI consumes the new public read.

## Environment Availability

> No external dependencies — Phase 29 is purely internal Elixir. Skipping the table.

**Verified absent:** No new libraries, no new database/cache, no new network endpoints, no new build tools.

## Validation Architecture

> Phase 29 introduces no new domain code (only one read-only pure function `Foglet.Accounts.valid_status_transitions/1`) but introduces TUI lifecycle behavior with extensive surface area. Existing test infrastructure covers Phase 29 entirely.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | ExUnit (Elixir built-in test framework, version locked by Elixir release) |
| Config file | `test/test_helper.exs` (existing); per-test setup via `use FogletBbs.DataCase, async: false` |
| Quick run command | `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs` |
| Full suite command | `rtk mix test` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SYSOP-01 | Tab switch to BOARDS/LIMITS/SYSTEM/USERS auto-dispatches a load; no `"Press any key"` literal in `sysop.ex` | render-smoke + grep | `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs --only sysop_01` | ✅ (test file exists; new tests added) |
| SYSOP-02 | Each lifecycle slot is tagged enum; `[R] Retry` advertised on `{:error, _}` (reason ≠ `:forbidden`); pressing R re-dispatches; `{:error, :forbidden}` shows distinct panel and suppresses `[R] Retry` | unit (state) + render-smoke (injection) + integration (round-trip) | `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs --only sysop_02` | ✅ (test file exists; new tests added) |
| SYSOP-03 (amended by D-20/D-21) | Site Esc reseeds drafts (no inline copy); Enter persists with `Saved.` row from Phase 28 D-08 | integration | `rtk mix test test/foglet_bbs/tui/screens/sysop/site_form_test.exs` | ✅ (existing) |
| SYSOP-04 | `@site_keys` descriptions contain no `(D-\d+)`, `REQ-`, `Phase`, `Pitfall`, or `deliverable` (case-insensitive) | grep / property | `rtk mix test test/foglet_bbs/config/schema_test.exs --only sysop_04` (new test) | ❌ Wave 0 — new test file or extension needed |
| SYSOP-05 | USERS focused-`:active` row hides `[A] Approve`; pressing `A` is a no-op; injected `:invalid_transition` produces from→to copy | unit (UsersView) + integration (with stub) | `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs --only sysop_05` | ✅ (existing test file extended) |
| SYSOP-06 | INVITES focused row visibly distinct at 80×24; Enter on non-revoked focused row → `[X] Revoke` advertised; pressing `X` invokes `InvitesActions.revoke_*`; revoked focused row → `[X] Revoke` absent | render-smoke + integration | `rtk mix test test/foglet_bbs/tui/screens/shared/invites_surface_test.exs --only sysop_06` + `sysop_test.exs` | ✅ (test files exist; new tests added) |
| SYSOP-07 | Account/Moderation/Sysop command bars contain `1-N Jump` substring at 64×22 and 80×24 across INVITES-visible/hidden contexts; literal `{"1-6", "Jump"}` absent in moderation.ex | render-smoke + grep | `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs --only sysop_07` | ✅ (test file exists; new tests added) |

### Sampling Rate
- **Per task commit:** `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/accounts_test.exs --max-failures 1` — typically < 30s
- **Per wave merge:** `rtk mix test test/foglet_bbs/tui/` — 3-5 min
- **Phase gate:** `rtk mix precommit` (compile-warnings-as-errors + format + Credo + Sobelow + Dialyzer + full test suite) before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `test/foglet_bbs/config/schema_test.exs` — extend (or create) to assert the SYSOP-04 grep regex over `Foglet.Config.Schema.entries()` for the 5 `@site_keys` descriptions. Existing file at `test/foglet_bbs/config/` likely covers other validation; verify.
- [ ] `test/foglet_bbs/accounts_test.exs` — add `describe "valid_status_transitions/1"` block with one test per `from_status` (4 tests).
- [ ] `test/foglet_bbs/tui/screens/sysop_test.exs` — add new `describe` blocks: lifecycle tagged enum round-trip, tab-switch auto-load, retry re-dispatch, forbidden panel, USERS gating with focused `:active`, USERS injected `:invalid_transition` from→to copy.
- [ ] `test/foglet_bbs/tui/screens/shared/invites_surface_test.exs` — extend with focus-highlight assertion at 80×24 (focused row tokens differ from unfocused).
- [ ] `test/foglet_bbs/tui/layout_smoke_test.exs` — add `1-N Jump` substring assertions for Account / Moderation / Sysop at both 64×22 and 80×24, INVITES-visible and INVITES-hidden.
- [ ] **Grep tests (mix-task style or in a dedicated `grep_test.exs`):**
  - No `"Press any key"` in `lib/foglet_bbs/tui/screens/sysop.ex`.
  - No `Raxol.Core.Runtime.Command.task` substring in `lib/foglet_bbs/tui/screens/sysop/` or `lib/foglet_bbs/tui/screens/sysop.ex`.
  - No `{"1-6", "Jump"}` literal in `lib/foglet_bbs/tui/screens/moderation.ex` or `lib/foglet_bbs/tui/screens/account.ex`.
  - The Schema description regex test (also covers SYSOP-04).

*If no other gaps: existing test infrastructure (DataCase, RenderHelpers, RenderFixtures, sysop_test.exs harness) covers all Phase 29 requirements with extensions only.*

## Security Domain

> `security_enforcement` is enabled by default. This phase touches authorization-adjacent code paths (status-transition advertising, sysop role gating, INVITES revoke surface) but adds no new authorization rules. The existing Bodyguard policies remain authoritative.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Phase 29 does not touch login/credentials. |
| V3 Session Management | no | Phase 29 reads `state.current_user` from existing session plumbing; no new session state. |
| V4 Access Control | yes | `Foglet.Authorization` (Bodyguard) + the existing `:manage_user_status` permission at `accounts.ex:250`. Phase 29 SURFACES `{:error, :forbidden}` honestly; it does NOT add new authorization rules. UsersView's keybind gating is a UI affordance, NOT authorization (the writer's `permit_status_transition/2` re-checks server-side). |
| V5 Input Validation | partial | UsersView keybind gating is input filtering at the screen layer; the domain boundary still validates. SiteForm's `validate_delivery_verification_pair/1` (Phase 28) runs pre-flight before `Foglet.Config.put/3`. |
| V6 Cryptography | no | No new crypto; status transitions are not signed/MACed. |

### Known Threat Patterns for Sysop screen lifecycle

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Hidden keybind treated as authorization | Elevation of Privilege (EoP) | UsersView keybind gating is UI-only — the writer (`Accounts.transition_user_status/3`) re-checks `permit_status_transition/2` (`accounts.ex:255`). A user who bypasses the UI and sends a forbidden transition still gets `{:error, :invalid_transition}`. CONTEXT.md D-15 + AGENTS.md "Hidden or disabled UI is never authorization." |
| `{:error, :forbidden}` panel as auth check | EoP | The panel is rendered AFTER the boundary call returned `:forbidden`. The boundary is the gate; the panel is just honest reporting. Confirmed by the existing `Foglet.Accounts.list_user_status_admin_targets/1` shape at `accounts.ex:286+`. |
| Sysop role drift via direct screen routing | EoP / Pitfall 3 | `Sysop.render/1` already calls `ShellVisibility.sysop_visible?/1` defensively at `sysop.ex:49-53`. Phase 29 inherits this — no change. |
| Stale `{:loaded, sub}` after role demotion | Information Disclosure | The slot caches the loaded payload; if the operator is demoted between load and re-render, the cached struct is still rendered. Mitigation: writer-side recheck (already present); reading stale state-admin targets is a read-only information disclosure of users the operator was previously authorized to see. Acceptable risk in v1.4 — `SYSOP-FUT-01` (background prefetch / staleness tracking) is deferred. |
| INVITES `[X] Revoke` race after revoke | Tampering | Revoke goes through `InvitesActions.revoke_selected/2` (`invites_actions.ex:42-50`) which calls `Foglet.Accounts.Invites.revoke_invite/2`. The boundary handles already-revoked invites with `{:error, :unavailable}`. No race-handling change in Phase 29. |
| Operator copy leak via field description | Information Disclosure | CONTEXT.md D-22 forces removal of internal planning IDs from `@site_keys` descriptions; SPEC §SYSOP-04 grep test covers this. |

## Project Constraints (from CLAUDE.md / AGENTS.md)

These directives must be honored verbatim by the planner and executor; they have the same authority as locked CONTEXT.md decisions.

- **Use `rtk` as the shell command prefix** — every `mix` invocation in plans/tests is `rtk mix ...`.
- **`Foglet.*` is domain; `FogletBbs.*` / `FogletBbsWeb.*` is Phoenix infrastructure** — Phase 29 changes live in `Foglet.TUI.*` and `Foglet.Accounts.*`. No FogletBbsWeb changes.
- **Domain workflows in contexts, not controllers/SSH callbacks/TUI render functions** — the new `valid_status_transitions/1` lives in `Foglet.Accounts`, not in `UsersView`. (CONTEXT.md D-14 already encodes this.)
- **Programmatically set foreign keys before changeset construction** — N/A; Phase 29 has no schema changes.
- **Per-board message numbers, board server single-writer** — N/A; Phase 29 doesn't touch posts/threads.
- **Authorization scopes are `:site` and `{:board, board_id}`** — N/A; Phase 29 reuses `:site` (e.g. `Bodyguard.permit(Foglet.Authorization, :manage_user_status, actor, :site)`).
- **Read pointers** — N/A; Phase 29 doesn't touch read pointers.
- **`Foglet.Config.get!/get/put` for runtime config** — SiteForm's persistence path uses `Foglet.Config.put/3` with actor. (Phase 28 already shipped this.)
- **`Foglet.TUI.Command.task/2` is the only sanctioned task wrapper** — CONTEXT.md D-04 + grep test forbid `Raxol.Core.Runtime.Command.task/1` from any `Sysop.*` module.
- **All theme color routing through `Foglet.TUI.Theme`** — every loading/error/forbidden/selected slot in Phase 29 routes through theme; no `IO.ANSI.*` literals.
- **Screen-vs-widget boundaries** — INVITES focus highlight stays at the surface (`Shared.InvitesSurface`); the `[X] Revoke` advertising lives in the screen's command bar (`Sysop.sysop_commands/1`).
- **`mix foglet.tui.render <screen>` for visual inspection** — use this for layout audits during plan execution; non-test, non-behavioral.
- **`use start_supervised!/1`; avoid `Process.sleep/1`/`Process.alive?/1`** — Phase 29 tests don't spawn processes; the existing `DataCase` setup is sufficient.
- **Run `rtk mix precommit` when code changes are complete** — phase gate before `/gsd-verify-work`.

## Sources

### Primary (HIGH confidence — verified by reading the code)
- `lib/foglet_bbs/tui/screens/sysop.ex:1-289` — Sysop screen shell, tab dispatch, render_tab_body
- `lib/foglet_bbs/tui/screens/sysop/state.ex:1-111` — State struct, tagged-enum target slots
- `lib/foglet_bbs/tui/screens/sysop/site_form.ex:1-261` — Phase 28 Modal.Form wrapper, persist_payload, Esc reseed
- `lib/foglet_bbs/tui/screens/sysop/users_view.ex:1-218` — USERS submodule, footer, error_message, transition flow
- `lib/foglet_bbs/tui/screens/sysop/boards_view.ex:1-60` — Submodule struct shape (becomes `{:loaded, _}` payload)
- `lib/foglet_bbs/tui/screens/sysop/limits_form.ex:1-60` — Submodule struct shape
- `lib/foglet_bbs/tui/screens/sysop/system_snapshot.ex:1-60` — Submodule struct shape
- `lib/foglet_bbs/tui/app.ex:300-340, 500-530, 900-960, 1040-1115, 1300-1360` — `do_update/2`, navigate, moderation triad, `process_screen_commands/2`, `task_error` handler
- `lib/foglet_bbs/tui/command.ex:1-39` — `Foglet.TUI.Command.task/2` wrapper contract
- `lib/foglet_bbs/accounts.ex:170-290` — `permit_status_transition/2`, `transition_user_status/3`, `list_user_status_admin_targets/1`
- `lib/foglet_bbs/config/schema.ex:1-231` — `@entries`, `@site_keys` description strings, `fetch_spec/1`
- `lib/foglet_bbs/tui/screens/account.ex:1-200` — `@key_bar`, `tab_labels/1`
- `lib/foglet_bbs/tui/screens/moderation.ex:1-310` — `@key_list`, `tab_labels_from_tabs/1`, dispatch precedent
- `lib/foglet_bbs/tui/screens/shared/invites_surface.ex:1-170` — Live render path (ConsoleTable) and legacy raw-map path
- `lib/foglet_bbs/tui/screens/shared/invites_actions.ex:1-131` — `revoke_selected/2`, `handle_key/3`, key dispatch shapes
- `lib/foglet_bbs/tui/widgets/modal/form.ex:1-60, 400-420` — `submit_state` machine, `Saved.` row rendering
- `lib/foglet_bbs/tui/render_fixtures.ex:240-320` — Sysop fixture, sysop role at handle "alice"
- `test/foglet_bbs/tui/screens/sysop_test.exs:1-180` — Existing harness, `build_state/1`, `put_in([:screen_state, :sysop], ss)` injection idiom
- `test/foglet_bbs/tui/layout_smoke_test.exs:1-100` — `@dimensions = %{width: 80, height: 24}`, `@phase_16_dimensions = [{64, 22}, {80, 24}, {132, 50}]` patterns
- `test/support/foglet/tui/render_helpers.ex:1-55` — `collect_text_values/1` DFS walker for substring assertions
- `.planning/phases/28-modal-form-substrate/28-CONTEXT.md` — Phase 28 D-08 (Saved row), D-10..D-12 (no-discard-copy), D-17..D-21 (SiteForm wrapper)
- `.planning/phases/29-sysop-tab-lifecycle-bodies/29-CONTEXT.md` — All D-01..D-27 decisions
- `.planning/phases/29-sysop-tab-lifecycle-bodies/29-SPEC.md` — SYSOP-01..07 acceptance (note D-20/D-21 amends SYSOP-03)
- `AGENTS.md` — TUI section, context boundary rules, theme routing, `Foglet.TUI.Command` mandate

### Secondary (MEDIUM confidence)
- None — every claim above traces to a verified code-read source.

### Tertiary (LOW confidence)
- None — no WebSearch was needed; this phase is fully internal.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every primitive (Foglet.TUI.Command, Modal.Form submit_state, theme.selected.*, ConsoleTable, etc.) verified in-tree
- Architecture: HIGH — Moderation triad is a verbatim structural twin; first-entry guard via `do_update({:navigate, _}, _)` is precedented at `app.ex:321-322`
- Pitfalls: HIGH — every pitfall traces to a specific line in current code (delegate_to_submodule fallback at sysop.ex:235; @key_bar compile-time freeze at account.ex:42; SPEC vs Phase 28 D-12 conflict at SPEC SYSOP-03 vs CONTEXT.md D-20)
- Tests: HIGH — existing harness patterns are well-understood; no new test infrastructure needed
- Open questions: 3 (one architectural, two semantic) — flagged for plan-phase confirmation

**Research date:** 2026-04-27
**Valid until:** 2026-05-27 (30 days; this is internal Foglet code with no external library churn)
