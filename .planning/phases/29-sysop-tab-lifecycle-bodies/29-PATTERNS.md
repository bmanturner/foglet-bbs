# Phase 29: Sysop Tab Lifecycle & Bodies — Pattern Map

**Mapped:** 2026-04-27
**Files analyzed:** 13 modified + 5 new tests
**Analogs found:** 13 / 13 (every modified file has a strong in-tree analog)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `lib/foglet_bbs/tui/app.ex` (load triad: 4 dispatch + 4 result + put_sysop_*) | app dispatch | request-response (async task) | `app.ex:513-533` (moderation triad) + `app.ex:1081-1116` (put_moderation_*) | exact (verbatim structural twin) |
| `lib/foglet_bbs/tui/app.ex` (`{:navigate, :sysop}` chain) | app dispatch | event-driven | `app.ex:321-322` (moderation navigate chain) | exact |
| `lib/foglet_bbs/tui/screens/sysop.ex` (`render_tab_body/3`, `delegate_to_submodule/5`, `handle_key/2` tab-changed branch, `[R] Retry`, `jump_hint`, `sysop_commands/1`) | screen | event-driven | `lib/foglet_bbs/tui/screens/moderation.ex:77-108, 217-223` + `sysop.ex` self (sections 170-228) | role + flow match |
| `lib/foglet_bbs/tui/screens/sysop/state.ex` (tagged-enum slots) | state | data shape | `sysop/state.ex:22-44` self; tagged enum is novel — no full analog | partial (defstruct shape only) |
| `lib/foglet_bbs/tui/screens/sysop/site_form.ex` (on_submit/on_cancel verification) | screen submodule | request-response | `site_form.ex:60-107, 135-211` self (already Modal.Form-wrapped post-Phase 28) | exact (no structural change) |
| `lib/foglet_bbs/tui/screens/sysop/users_view.ex` (footer + handle_key gating + from→to copy) | screen submodule | render-time | `users_view.ex:23, 60-78, 100, 204-213` self (footer/handle_key today) | role-match (rewrite in place) |
| `lib/foglet_bbs/tui/screens/sysop/{boards_view,limits_form,system_snapshot}.ex` | screen submodule | data shape | unchanged (struct becomes `{:loaded, _}` payload) | identity |
| `lib/foglet_bbs/accounts.ex` (`valid_status_transitions/1`) | domain context | pure predicate | `accounts.ex:187-191` (private `permit_status_transition/2`) | exact (sibling public read) |
| `lib/foglet_bbs/config/schema.ex` (`@site_keys` description rewrites) | schema config | data shape | `config/schema.ex:49-125` self (`@entries`) | identity (string-only rewrites) |
| `lib/foglet_bbs/tui/screens/account.ex` (`@key_bar` → render-time fn) | screen | render-time | `sysop.ex:61` (existing dynamic `jump_hint` if-expr) | role-match |
| `lib/foglet_bbs/tui/screens/moderation.ex` (`@key_list` → render-time fn) | screen | render-time | `sysop.ex:61` (existing dynamic `jump_hint` if-expr) | role-match |
| `lib/foglet_bbs/tui/screens/shared/invites_surface.ex` (focused-row highlight) | shared surface | render-time | `users_view.ex:131-135` (selected-row text wrapping) | exact (idiom transplant) |
| `lib/foglet_bbs/tui/screens/shared/invites_actions.ex` | shared actions | request-response | unchanged (consumed as-is by new `[X] Revoke` advertising) | identity |
| `test/foglet_bbs/accounts_test.exs` (+`valid_status_transitions/1`) | test | unit | existing `transition_user_status/3` describe blocks | exact |
| `test/foglet_bbs/tui/screens/sysop_test.exs` (+lifecycle, retry, forbidden, USERS gating) | test | render-smoke + integration | existing `sysop_test.exs` `build_state/1`, `put_in([:screen_state, :sysop], ss)` injection | exact |
| `test/foglet_bbs/tui/screens/shared/invites_surface_test.exs` (+focus highlight) | test | render-smoke | existing `users_view` selection tests | exact |
| `test/foglet_bbs/tui/layout_smoke_test.exs` (+`1-N Jump` substring assertions) | test | render-smoke | existing `@dimensions`, `@phase_16_dimensions` patterns | exact |

---

## Pattern Assignments

### `lib/foglet_bbs/tui/app.ex` — Sysop Load Triad (D-01..D-02)

**Analog:** `app.ex:513-533, 1081-1116` (Moderation load triad — verbatim structural twin)

**Dispatch clause** (analog at `app.ex:513-525`):

```elixir
defp do_update({:load_moderation_workspace}, state) do
  user = state.current_user
  moderation_mod = domain_module(state, :moderation)

  state = put_moderation_loading(state)

  task =
    Foglet.TUI.Command.task(:load_moderation_workspace, fn ->
      {:moderation_workspace_loaded, moderation_mod.workspace_snapshot(user)}
    end)

  {state, [task]}
end
```

**Result clauses** (analog at `app.ex:527-533`):

```elixir
defp do_update({:moderation_workspace_loaded, {:ok, snapshot}}, state) when is_map(snapshot) do
  {%{state | screen_state: put_moderation_snapshot(state, snapshot)}, []}
end

defp do_update({:moderation_workspace_loaded, {:error, reason}}, state) do
  {%{state | screen_state: put_moderation_error(state, reason)}, []}
end
```

**Put helpers** (analog at `app.ex:1081-1123`):

```elixir
defp put_moderation_loading(state) do
  ss =
    state
    |> moderation_screen_state()
    |> Map.put(:loading?, true)
    |> Map.put(:error, nil)

  %{state | screen_state: Map.put(state.screen_state || %{}, :moderation, ss)}
end

defp put_moderation_snapshot(state, snapshot) do
  ss =
    state
    |> moderation_screen_state()
    |> Map.merge(%{
      scopes: Map.get(snapshot, :scopes, []),
      ...
      loading?: false,
      error: nil
    })

  Map.put(state.screen_state || %{}, :moderation, ss)
end

defp put_moderation_error(state, reason) do
  ss =
    state
    |> moderation_screen_state()
    |> Map.put(:loading?, false)
    |> Map.put(:error, reason)

  Map.put(state.screen_state || %{}, :moderation, ss)
end

defp moderation_screen_state(state) do
  case Map.get(state.screen_state || %{}, :moderation) do
    %Foglet.TUI.Screens.Moderation.State{} = ss -> ss
    _other -> Screens.Moderation.init_screen_state()
  end
end
```

**Diff shape for Phase 29:**
- Replace flat `loading?: bool / error: term` with the tagged enum (`:loading | {:loaded, sub} | {:error, reason}`).
- Sysop helpers take a `slot` atom argument (`:boards_view | :limits_form | :system_snapshot | :users_view`) since one screen has four lifecycle slots — moderation has one snapshot.
- Dispatch closure binds `user = state.current_user` and `accounts_mod = domain_module(state, :accounts)` BEFORE the task closure (Pitfall 8) — same as moderation precedent.
- Four parallel triads (BOARDS, LIMITS, SYSTEM, USERS).

---

### `lib/foglet_bbs/tui/app.ex` — `{:navigate, :sysop}` First-Entry Chain (D-06)

**Analog:** `app.ex:317-326`:

```elixir
cond do
  screen == :main_menu and new_state.current_user ->
    do_update({:load_oneliners}, new_state)

  screen == :moderation and new_state.current_user ->
    do_update({:load_moderation_workspace}, new_state)

  true ->
    {new_state, []}
end
```

**Diff shape for Phase 29:** add a `screen == :sysop and new_state.current_user -> maybe_dispatch_initial_sysop_load(new_state)` arm. The helper inspects `state.screen_state[:sysop].active_tab`'s label and re-enters `do_update/2` with the matching `{:load_sysop_*}` tuple — `{state, []}` for SITE/INVITES (sync). Idempotent: `dispatch_if_not_loaded/3` (Sysop side) gates on `:not_loaded`.

---

### `lib/foglet_bbs/tui/screens/sysop.ex` — Lifecycle Render + Tab-Switch Dispatch (D-05, D-08, D-09)

**Analog (render structure):** `sysop.ex:120-153` (existing `render_tab_body/3`)

**Existing code that must change** (`sysop.ex:148-153`):

```elixir
defp render_tab_body("USERS", ss, theme) do
  case ss.users_view do
    nil -> placeholder("Press any key to load user status administration.", theme)
    view -> UsersView.render(view, theme)
  end
end
```

**Diff shape:** pattern-match on the tagged enum BEFORE the submodule render. `{:error, :forbidden}` MUST appear before the `{:error, _}` catch-all (Pitfall 3). Reuse `theme.dim.fg` for loading (matches `invites_surface.ex:61` and `moderation.ex:218`), `theme.warning.fg` for forbidden, `theme.error.fg` for generic error.

```elixir
defp render_tab_body("USERS", ss, theme) do
  case ss.users_view do
    :not_loaded -> loading_panel(theme)
    :loading -> loading_panel(theme)
    {:loaded, sub} -> UsersView.render(sub, theme)
    {:error, :forbidden} -> forbidden_panel(theme)
    {:error, _other} -> error_panel("users", theme)
  end
end

defp loading_panel(theme),
  do: column(style: %{gap: 0}, do: [text("Loading…", fg: theme.dim.fg)])

defp forbidden_panel(theme),
  do: column(style: %{gap: 0}, do: [text("Insufficient role to view this tab.", fg: theme.warning.fg)])

defp error_panel(tab, theme),
  do: column(style: %{gap: 0}, do: [text("Could not load #{tab}. Press R to retry.", fg: theme.error.fg)])
```

**`delegate_to_submodule/5` analog** (`sysop.ex:234-238` — to be rewritten):

```elixir
# BEFORE (today):
defp delegate_to_submodule(event, state, ss, field, module) do
  sub = Map.get(ss, field) || module.init(current_user: state.current_user)
  {new_sub, events} = module.handle_key(event, sub)
  apply_submodule_result(state, ss, field, new_sub, sub, events)
end
```

**Diff shape:** require `{:loaded, sub}` pattern match. On any other value (`:not_loaded | :loading | {:error, _}`) return `:no_match`.

```elixir
defp delegate_to_submodule(event, state, ss, field, module) do
  case Map.get(ss, field) do
    {:loaded, sub} ->
      {new_sub, events} = module.handle_key(event, sub)
      apply_submodule_result(state, ss, field, {:loaded, new_sub}, {:loaded, sub}, events)

    _other ->
      :no_match
  end
end
```

**Tab-switch trigger analog** (`sysop.ex:170-192`):

```elixir
def handle_key(event, state) do
  ss = get_screen_state(state)
  {new_tabs, action} = Tabs.handle_event(event, ss.tabs)

  if action == nil and new_tabs == ss.tabs do
    delegate_to_active_tab(event, state, ss)
  else
    new_active = case action do
      {:tab_changed, idx} -> idx
      _ -> ss.active_tab
    end

    new_ss =
      ss
      |> Map.merge(%{tabs: new_tabs, active_tab: new_active})
      |> maybe_load_invites_on_entry(state)

    new_screen_state = Map.put(state.screen_state, :sysop, new_ss)
    {:update, %{state | screen_state: new_screen_state}, []}
  end
end
```

**Diff shape:** before constructing the final return tuple, call `maybe_dispatch_lifecycle_load(new_ss, new_active)` which returns `{new_ss', commands}`; emit those commands instead of `[]`. The helper transitions `:not_loaded → :loading` AND emits the matching dispatch tuple in one pass:

```elixir
defp maybe_dispatch_lifecycle_load(ss, active_idx) do
  case Enum.at(State.tab_labels(ss), active_idx) do
    "BOARDS" -> dispatch_if_not_loaded(ss, :boards_view, {:load_sysop_boards})
    "LIMITS" -> dispatch_if_not_loaded(ss, :limits_form, {:load_sysop_limits})
    "SYSTEM" -> dispatch_if_not_loaded(ss, :system_snapshot, {:load_sysop_system})
    "USERS"  -> dispatch_if_not_loaded(ss, :users_view, {:load_sysop_users})
    _ -> {ss, []}
  end
end

defp dispatch_if_not_loaded(ss, slot, dispatch_tuple) do
  case Map.get(ss, slot) do
    :not_loaded -> {Map.put(ss, slot, :loading), [dispatch_tuple]}
    _ -> {ss, []}
  end
end
```

**`jump_hint` analog** (`sysop.ex:61` — already dynamic):

```elixir
# BEFORE:
jump_hint = if "INVITES" in State.tab_labels(ss), do: "1-6", else: "1-5"
# AFTER:
jump_hint = "1-#{length(State.tab_labels(ss))}"
```

**`[R] Retry` advertising** (D-13 — new helper for `sysop_commands/1` at `sysop.ex:83-97`):

```elixir
defp maybe_add_retry(groups, ss) do
  active_label = Enum.at(State.tab_labels(ss), ss.active_tab)
  case Map.get(ss, slot_for(active_label) || :__none__) do
    {:error, reason} when reason != :forbidden ->
      groups ++ [%{label: "Action", commands: [%{key: "R", label: "Retry", priority: 5}]}]
    _ -> groups
  end
end
```

---

### `lib/foglet_bbs/tui/screens/sysop/state.ex` — Tagged-Enum Slots (D-07, D-10)

**Analog:** `state.ex:22-44` self (existing slot defaults `nil`)

**Existing code:**

```elixir
@type t :: %__MODULE__{
        ...
        site_form: term() | nil,
        limits_form: term() | nil,
        boards_view: term() | nil,
        system_snapshot: term() | nil,
        users_view: term() | nil
      }

defstruct [
  :tabs,
  active_tab: 0,
  tab_labels: @base_tabs,
  invites: InvitesState.new(),
  site_form: nil,
  limits_form: nil,
  boards_view: nil,
  system_snapshot: nil,
  users_view: nil
]
```

**Diff shape:** `site_form` stays `nil`-default (D-03 — SITE remains sync). Four lifecycle slots flip to `:not_loaded` default and a new `lifecycle/1` typespec:

```elixir
@type lifecycle(struct_t) ::
        :not_loaded
        | :loading
        | {:loaded, struct_t}
        | {:error, atom()}

@type t :: %__MODULE__{
        ...
        site_form: term() | nil,
        limits_form: lifecycle(LimitsForm.t()),
        boards_view: lifecycle(BoardsView.t()),
        system_snapshot: lifecycle(SystemSnapshot.t()),
        users_view: lifecycle(UsersView.t())
      }

defstruct [
  ...
  limits_form: :not_loaded,
  boards_view: :not_loaded,
  system_snapshot: :not_loaded,
  users_view: :not_loaded
]
```

---

### `lib/foglet_bbs/tui/screens/sysop/users_view.ex` — Render-Time Footer + From→To Copy (D-15, D-16)

**Analog:** `users_view.ex:60-78, 100, 204-213` self.

**Existing handle_key + footer** (today at `users_view.ex:23, 60-78, 100`):

```elixir
@footer "[A] Approve  [R] Reject  [S] Suspend  [U] Reactivate  [j/k] Move"

def handle_key(%{key: :char, char: c}, state) when c in ["A", "a"],
  do: transition(state, :active)
def handle_key(%{key: :char, char: c}, state) when c in ["R", "r"],
  do: transition(state, :rejected)
def handle_key(%{key: :char, char: c}, state) when c in ["S", "s"],
  do: transition(state, :suspended)
def handle_key(%{key: :char, char: c}, state) when c in ["U", "u"],
  do: transition(state, :active)
def handle_key(_event, state), do: {state, []}

# in render/2:
... ++ [body, text(""), text(@footer, fg: theme.dim.fg)]
```

**Existing success-message format mirror** (`users_view.ex:204-208`):

```elixir
defp success_message(handle, from, to, {:failed, _reason}),
  do: "Status changed: @#{handle} #{from} -> #{to}. Notification failed."

defp success_message(handle, from, to, _delivery),
  do: "Status changed: @#{handle} #{from} -> #{to}."
```

**Diff shape:**

1. Replace `@footer` (constant) with render-time `footer_text/1` consulting `Accounts.valid_status_transitions(focused_status)` — only advertise keys whose target is in the allowed set. **Disambiguation rule** (Open Question A2 in RESEARCH.md — confirm with planner): show `[A]` only when focused row is `:pending`, `[U]` only when focused row is `:suspended` (both target `:active` but pick by source).

2. Replace each char-key clause with a guard that no-ops disallowed transitions:

```elixir
def handle_key(%{key: :char, char: c}, state) when c in ["A", "a"],
  do: maybe_transition(state, :active, :pending)
defp maybe_transition(%__MODULE__{rows: []} = state, _, _), do: {state, []}
defp maybe_transition(state, target, required_from) do
  {focused_status, _} = Enum.at(state.rows, state.selection_index)
  if focused_status == required_from and target in Accounts.valid_status_transitions(focused_status) do
    transition(state, target)
  else
    {state, []}
  end
end
```

3. Replace `error_message(:invalid_transition)` (today at `users_view.ex:213`) with from→to builder. Mirror the existing success format:

```elixir
# BEFORE:
defp error_message(:invalid_transition), do: "Invalid status transition."

# AFTER (call site at users_view.ex:200 must pass handle/from/to):
defp invalid_transition_message(handle, from, to),
  do: "Cannot change @#{handle} from #{to_string(from)} to #{to_string(to)}."

# Updated transition error branch (was: line 199-200):
{:error, :invalid_transition} ->
  {_status, focused_user} = Enum.at(state.rows, state.selection_index)
  msg = invalid_transition_message(focused_user.handle, focused_user.status, target_status)
  {%{state | message: msg}, []}
```

**Output substring constraint (D-16):** must NOT contain `"invalid_transition"`.

---

### `lib/foglet_bbs/tui/screens/sysop/site_form.ex` — `on_submit` / `on_cancel` Verification (D-18..D-21)

**Analog:** `site_form.ex:60-211` self (already Modal.Form-wrapped post-Phase 28).

**Existing on_cancel/Esc handler** (`site_form.ex:80-83, 102-104`):

```elixir
def handle_key(%{key: :escape}, %SState{} = state) do
  # FORM-06 / D-12: reseed drafts; no inline status copy.
  {SState.reseed_drafts(state), []}
end

# in handle_key/2 main branch:
case action do
  :submitted -> finalize_submit(state, new_form)
  :cancelled -> {SState.reseed_drafts(state), []}
  _ -> {sync_back(state, new_form), []}
end
```

**Existing on_submit/`Saved.` flow** (`site_form.ex:204-211`):

```elixir
if events == [] do
  # All persisted: drive submit_state to :saved so the form shows "Saved." once.
  final_form2 = ModalForm.set_submit_state(new_form, :saved)
  {sync_back(final_state, final_form2), []}
else
  {final_state, events}
end
```

**Diff shape for Phase 29:** **No structural change**. Verify Phase 28's substrate honors D-18 (Enter→`Foglet.Config.put/3`, all-keys-success → `set_submit_state(:saved)`, any-failure → `{:error, msg}`) and D-20 (Esc reseeds, no `status_message`). Phase 29 plans a regression test that asserts (a) post-Esc rendered drafts equal saved Config, (b) post-Enter rendered output contains `"Saved."` substring (verbatim from Phase 28 D-08), (c) Esc does not navigate away. **No code edits in this file** unless verification reveals a Phase 28 gap.

---

### `lib/foglet_bbs/accounts.ex` — `valid_status_transitions/1` (D-14)

**Analog:** `accounts.ex:187-191` (private `permit_status_transition/2`):

```elixir
defp permit_status_transition(:pending, :active), do: :ok
defp permit_status_transition(:pending, :rejected), do: :ok
defp permit_status_transition(:active, :suspended), do: :ok
defp permit_status_transition(:suspended, :active), do: :ok
defp permit_status_transition(_from, _to), do: {:error, :invalid_transition}
```

**Diff shape:** add a sibling public function derived from the same predicate. Place adjacent to `permit_status_transition/2` so the rules-source-of-truth invariant is visually obvious.

```elixir
@doc """
Returns the list of valid target statuses for `from_status`.

Sourced from the same predicate `transition_user_status/3` enforces
server-side (`permit_status_transition/2`); using this function for
UI-side keybind gating guarantees no drift.
"""
@spec valid_status_transitions(:pending | :active | :suspended | :rejected) ::
        [:active | :suspended | :rejected]
def valid_status_transitions(:pending), do: [:active, :rejected]
def valid_status_transitions(:active), do: [:suspended]
def valid_status_transitions(:suspended), do: [:active]
def valid_status_transitions(:rejected), do: []
```

`permit_status_transition/2` stays private; `transition_user_status/3` (`accounts.ex:249-274`) keeps using the existing private guard for symmetry.

---

### `lib/foglet_bbs/config/schema.ex` — `@site_keys` Description Rewrites (D-22, D-23)

**Analog:** `config/schema.ex:49-125` self (`@entries` literal).

**Existing strings** (lines 54, 63, 90, 99-100, 119-120):

```elixir
description: "Account registration policy (D-02/D-03): open | invite_only | sysop_approved",
description: "Who may generate invite codes (D-04): sysop_only | mods | any_user",
description: "Outbound transactional delivery mode (MAIL-01): email | no_email",
description: "When false, new registrations skip verify and existing confirmed_at: nil users gain access on login (Phase 6 D-01)",
description: "Per-user invite generation cap when invite_code_generators == \"any_user\" (INVT-07 D-04). 0 = unlimited.",
```

**Diff shape:** replace verbatim with D-23 literals (no enum value lists inlined; operators discover via Space-cycle):

```elixir
description: "How new accounts are created.",
description: "Who can generate invite codes.",
description: "Whether outbound email is sent.",
description: "Require email verification before login.",
description: "Per-user invite cap (0 = unlimited).",
```

**Acceptance regex** (case-insensitive): `(D-\d+|REQ-[A-Z]+-\d+|Phase \d+|Pitfall \d+|deliverable)/i` — verified zero matches against the proposed strings (RESEARCH.md A7).

---

### `lib/foglet_bbs/tui/screens/account.ex` — `@key_bar` → Render-Time Builder (D-26)

**Analog (existing pattern):** `sysop.ex:61` (already-dynamic `jump_hint`).

**Existing code** (`account.ex:42-48, 73`):

```elixir
@key_bar [
  {"←/→", "Tab"},
  {"Tab", "Field"},
  {"Enter", "Save"},
  {"Esc", "Cancel"},
  {"Ctrl+Q", "Back"}
]
# call site:
ScreenFrame.render(preview_state(state, theme), account_chrome(), content, @key_bar)
```

**Diff shape:** convert to a function that consults `length(tab_labels(ss))` and inserts the Jump pair between Tab and Field:

```elixir
defp key_bar(ss) do
  [
    {"←/→", "Tab"},
    {jump_hint(length(tab_labels(ss))), "Jump"},
    {"Tab", "Field"},
    {"Enter", "Save"},
    {"Esc", "Cancel"},
    {"Ctrl+Q", "Back"}
  ]
end

defp jump_hint(n) when is_integer(n) and n > 0, do: "1-#{n}"
```

Update call site at `account.ex:73`: `ScreenFrame.render(..., key_bar(ss))`.

---

### `lib/foglet_bbs/tui/screens/moderation.ex` — `@key_list` → Render-Time Builder (D-26)

**Analog:** `sysop.ex:61` (dynamic) + `account.ex` post-rewrite.

**Existing code** (`moderation.ex:44, 126`):

```elixir
@key_list [{"←/→", "Tab"}, {"1-6", "Jump"}, {"Q", "Back"}]
# call site:
ScreenFrame.render(state, moderation_chrome(), content, @key_list)
```

**Diff shape:**

```elixir
defp key_list(ss),
  do: [
    {"←/→", "Tab"},
    {jump_hint(length(tab_labels_from_tabs(ss))), "Jump"},
    {"Q", "Back"}
  ]

defp jump_hint(n) when is_integer(n) and n > 0, do: "1-#{n}"
```

Replace literal `{"1-6", "Jump"}` (verified by grep test). Update call site at `moderation.ex:126`.

---

### `lib/foglet_bbs/tui/screens/shared/invites_surface.ex` — Focused-Row Highlight (D-24)

**Analog:** `users_view.ex:124-136` (selected-row text wrapping idiom):

```elixir
row_texts =
  rows
  |> Enum.with_index()
  |> Enum.map(fn {{status, user}, row_idx} ->
    selected? = row_idx == idx
    label = "#{status}  @#{user.handle}  #{user.email}"

    if selected? do
      text(label, fg: theme.selected.fg, bg: theme.selected.bg)
    else
      text(label, fg: theme.primary.fg)
    end
  end)
```

**Diff shape (apply to legacy raw-map render path at `invites_surface.ex:108-118`):** Plan-phase first audits whether `ConsoleTable.render/2` (line 83) renders selection visibly at 80×24 SSH. If yes, no change. If no, mirror the UsersView idiom — wrap focused-row cells with `text(label, fg: theme.selected.fg, bg: theme.selected.bg)`:

```elixir
defp invite_rows(items, selected_index, theme) do
  SelectionList.render(items, selected_index, fn {item, _idx, selected?} ->
    label = row_label(item)
    if selected? do
      text(label, fg: theme.selected.fg, bg: theme.selected.bg)
    else
      ListRow.render(label, false, theme)
    end
  end)
end
```

No new theme slots.

---

### `lib/foglet_bbs/tui/screens/sysop.ex` — `[X] Revoke` Advertising (D-25)

**Analog:** `invites_actions.ex:41-50, 86-88` (existing revoke side effect — UNCHANGED):

```elixir
@spec revoke_selected(User.t(), InvitesState.t()) :: {:ok, InvitesState.t()}
def revoke_selected(%User{} = actor, %InvitesState{} = state) do
  case InvitesState.selected_item(state) do
    %{code: code} when is_binary(code) ->
      revoke_code(actor, code, state)
    _missing ->
      {:ok, InvitesState.with_error(state, "No invite is selected.")}
  end
end

# handle_key dispatch:
def handle_key(key, %User{} = actor, %InvitesState{} = state) when key in ["d", "D"] do
  revoke_selected(actor, state)
end
```

**Diff shape for Phase 29 (in `sysop.ex` `sysop_commands/1`):**

```elixir
defp maybe_add_revoke(groups, ss) do
  case Enum.at(State.tab_labels(ss), ss.active_tab) do
    "INVITES" ->
      case InvitesState.selected_item(ss.invites) do
        %{status: status} when status != :revoked ->
          # D-25: Enter on focused non-revoked row arms the [X] Revoke advertisement.
          # Plan-phase chooses the armed signal (e.g. :armed_revoke? on InvitesState)
          # — RESEARCH.md A3 flags this for confirmation.
          if Map.get(ss.invites, :armed_revoke?, false) do
            groups ++ [%{label: "Invite", commands: [%{key: "X", label: "Revoke", priority: 5}]}]
          else
            groups
          end
        _ -> groups
      end
    _ -> groups
  end
end
```

The `X` keypress dispatches the existing `InvitesActions` revoke path (no new domain code; route through `InvitesActions.handle_key("d", actor, invites)` or rebind `"X"` to the same handler).

---

### `test/foglet_bbs/accounts_test.exs` — `valid_status_transitions/1` Unit Tests

**Analog:** existing `transition_user_status/3` test blocks (same file).

**Diff shape:** four cases, mirror `permit_status_transition/2` clauses:

```elixir
describe "valid_status_transitions/1" do
  test ":pending → [:active, :rejected]" do
    assert Accounts.valid_status_transitions(:pending) == [:active, :rejected]
  end

  test ":active → [:suspended]" do
    assert Accounts.valid_status_transitions(:active) == [:suspended]
  end

  test ":suspended → [:active]" do
    assert Accounts.valid_status_transitions(:suspended) == [:active]
  end

  test ":rejected → []" do
    assert Accounts.valid_status_transitions(:rejected) == []
  end
end
```

---

### `test/foglet_bbs/tui/screens/sysop_test.exs` — Lifecycle / Retry / Forbidden / USERS Tests

**Analog:** existing `build_state/1`, `put_in([:screen_state, :sysop], ss)` injection idiom (`sysop_test.exs:127, 1155, 1171, 1456, 1469`).

**Diff shape:** new describe blocks — direct slot injection (no full async cycle in render-only tests; for round-trip tests, dispatch `{:load_sysop_users}` then `{:command_result, {:sysop_users_loaded, ...}}` through `App.do_update/2`):

```elixir
describe "USERS lifecycle" do
  test "{:error, :forbidden} renders forbidden panel and suppresses [R] Retry" do
    state = build_state() |> put_in([:screen_state, :sysop, :users_view], {:error, :forbidden})
    state = put_in(state[:screen_state][:sysop].active_tab, users_tab_idx())
    rendered = Sysop.render(state)
    text_values = collect_text_values(rendered)
    assert Enum.any?(text_values, &String.contains?(&1, "Insufficient role"))
    refute Enum.any?(text_values, &String.contains?(&1, "Retry"))
  end

  test "{:error, :timeout} renders generic error panel and advertises [R] Retry" do
    # ...
  end

  test "Pressing R when active tab is in {:error, _} re-dispatches the load tuple" do
    # ...
  end
end
```

---

### `test/foglet_bbs/tui/layout_smoke_test.exs` — `1-N Jump` Substring Assertions (D-27)

**Analog:** existing `@dimensions = %{width: 80, height: 24}` and `@phase_16_dimensions = [{64, 22}, {80, 24}, {132, 50}]` patterns.

**Diff shape:**

```elixir
test "Account/Moderation/Sysop emit '1-N Jump' substring at 64x22 and 80x24" do
  for {w, h} <- [{64, 22}, {80, 24}] do
    for screen <- [:account, :moderation, :sysop] do
      state = build_state(screen, terminal_size: {w, h})
      values = state |> render_screen() |> collect_text_values()
      assert Enum.any?(values, &String.contains?(&1, "1-"))
    end
  end
end
```

For Sysop, also verify INVITES-visible vs hidden actor contexts produce different N (5 vs 6).

---

## Shared Patterns

### Authentication / Role Gating
**Source:** `lib/foglet_bbs/tui/screens/shell_visibility.ex` + `Foglet.Authorization`
**Apply to:** Sysop screen entry (`Sysop.render/1` already calls `ShellVisibility.sysop_visible?/1` at `sysop.ex:49-53` — UNCHANGED).
**No new auth in Phase 29** — domain writers (`Accounts.transition_user_status/3`) re-check server-side.

### Theme Routing
**Source:** `Foglet.TUI.Theme` slots (`dim.fg`, `error.fg`, `warning.fg`, `selected.fg`, `selected.bg`, `accent.fg`, `primary.fg`)
**Apply to:** All Phase 29 panels. Loading uses `theme.dim.fg` (matches `invites_surface.ex:61`, `moderation.ex:218`). Forbidden uses `theme.warning.fg`. Generic error uses `theme.error.fg`. Focused INVITES row uses `theme.selected.fg`/`theme.selected.bg` (matches `users_view.ex:131-135`).

```elixir
# canonical loading panel
column(style: %{gap: 0}, do: [text("Loading…", fg: theme.dim.fg)])
```

**No new theme slots** (D-24 explicitly).

### Async Task Wrapping
**Source:** `Foglet.TUI.Command.task/2` (`command.ex:23-38`)
**Apply to:** Every new `{:load_sysop_*}` clause in `app.ex`. NEVER call `Raxol.Core.Runtime.Command.task/1` directly from any `Sysop.*` module (D-04 + grep test).

```elixir
Foglet.TUI.Command.task(:load_sysop_users, fn ->
  {:sysop_users_loaded, accounts_mod.list_user_status_admin_targets(user)}
end)
```

The wrapper catches exceptions and emits `{:task_error, op, reason}` — handled by `app.ex:948-958`.

### Closure Capture (Pitfall 8)
**Source:** `app.ex:514-525` (Moderation triad)
**Apply to:** All four sysop load clauses. Bind `user = state.current_user` and `accounts_mod = domain_module(state, :accounts)` BEFORE the `Foglet.TUI.Command.task/2` block. Closing over `state` directly causes test-override `domain_module/2` swaps to fail intermittently.

### Screen Command Dispatch Routing
**Source:** `app.ex:1342-1361` (`process_screen_commands/2`)
**Apply to:** No code change — auto-router already handles `{:load_sysop_*}` shape (any `is_atom(elem(t, 0))` tuple). Verified by RESEARCH.md A8.

### Pattern-Match Order: `:forbidden` Before `_` (Pitfall 3)
**Apply to:** `render_tab_body/3`, `maybe_add_retry/2`, any code that destructures `{:error, reason}`.

```elixir
# CORRECT:
case slot do
  {:error, :forbidden} -> forbidden_panel(theme)
  {:error, _other} -> error_panel(tab, theme)
end
```

Inverting the order silently routes `:forbidden` through generic-error + `[R] Retry`, looking broken when the user retries and sees `:forbidden` again.

---

## No Analog Found

Files with no close match in the codebase (none — every Phase 29 file has a strong existing analog or is identity-preserving):

| File | Role | Reason |
|------|------|--------|
| (none) | — | Every modified file has a precedent in-tree. The tagged-enum lifecycle is the only "novel" data shape, and even it has structural precedent in Phase 28's Modal.Form `submit_state` machine (`:idle | :submitting | :saved | {:error, _}`). |

---

## Metadata

**Analog search scope:**
- `lib/foglet_bbs/tui/app.ex` (load triad, navigate chain, process_screen_commands)
- `lib/foglet_bbs/tui/screens/sysop/` (all submodules)
- `lib/foglet_bbs/tui/screens/{account,moderation}.ex` (sibling tabbed screens)
- `lib/foglet_bbs/tui/screens/shared/{invites_surface,invites_actions}.ex`
- `lib/foglet_bbs/accounts.ex` (status transition predicates)
- `lib/foglet_bbs/config/schema.ex` (`@entries`)
- `lib/foglet_bbs/tui/command.ex` (task wrapper contract)

**Files scanned via Read:** 11
**Pattern extraction date:** 2026-04-27

## PATTERN MAPPING COMPLETE

**Phase:** 29 - Sysop Tab Lifecycle & Bodies — every modified file has a strong in-tree analog (Moderation load triad is the structural twin for the four Sysop loads; UsersView selection styling is the idiom for INVITES focus highlight; existing `permit_status_transition/2` clauses derive `valid_status_transitions/1`).
