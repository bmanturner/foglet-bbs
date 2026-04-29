defmodule Foglet.TUI.Screens.MainMenu do
  @moduledoc """
  BBS main menu — primary screen after login (SSH-07, SSH-08).

  Phase 0 adds role-gated entries for Account (D-01 — any authenticated user),
  Moderation (D-02 — `:mod`/`:sysop`), and Sysop (D-02 — `:sysop` only), all
  driven by `Foglet.TUI.Screens.ShellVisibility` predicates to prevent drift
  between MainMenu and the shells (Security Domain mitigation).

  MainMenu owns screen-local oneliner state in
  `Foglet.TUI.Screens.MainMenu.State`: recent rows, selection, pending hide
  targets, composer/hide requests, task results, and local oneliner lifecycle
  errors through `init/1`, `update/3`, and `render/2` (Phase 35 D-11/D-13).
  App remains the runtime/effect interpreter.

  Menu visibility is NOT authorization (Pitfall 3) — real actor-aware authz
  arrives in Phase 1. Phase 0 shells are all read-only placeholders.

  Phase 19 (Plan 01) introduces a single canonical `@main_menu_commands`
  descriptor list with a `:kind` tag (`:destination` or `:action`). Public
  `visible_destinations/1` and `visible_actions/1` are derived by filtering this
  one list, so destinations vs. actions cannot drift (D-01 single-source-of-truth).
  """

  @behaviour Foglet.TUI.Screen

  alias Foglet.Authorization
  alias Foglet.TUI.{Context, Effect}
  alias Foglet.TUI.Modal
  alias Foglet.TUI.Screens.{MainMenu.State, ShellVisibility}
  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

  import Raxol.Core.Renderer.View

  @default_terminal_size {80, 24}
  @oneliner_display_limit 5
  @oneliner_handle_limit 12
  # Body limit keeps a selected row within the right panel inner width at the
  # narrowest canonical terminal size: marker + "@" + handle + separator + body
  # = 2+1+12+2+17 = 34 columns at 64-wide.
  @oneliner_body_limit 17

  # Minimum Navigation panel inner width budget — the FLOOR for the
  # terminal-size-aware computation in nav_panel_inner_width/1. At 64×22 with
  # split_pane(ratio: {2,3}) and ScreenFrame outer border, the computed inner
  # width is ≈22; at 80×24 it is ≈28; at 132×50 it is ≈49. The floor protects
  # against missing/pathological `state.terminal_size` values and is the
  # smallest budget at which all glyph + label + key rows still fit
  # (D-12, RESEARCH.md Pitfall 1).
  @nav_panel_min_inner_width 20

  # Single canonical Main Menu command descriptor list (D-01).
  # `:kind` partitions entries into body destinations and command-bar actions;
  # `:visibility` is a tag consumed by the role/state gate inside
  # visible_destinations/1 and visible_actions/1. Both functions filter this
  # one list, so destinations vs. actions cannot drift.
  # Destination entries also carry their D-08 glyph atoms here, keeping the
  # rendered row shape in the canonical descriptor instead of a parallel map.
  # Theme-routed via theme.<slot>.fg (D-07/D-08); never hardcoded color atoms.
  # Per D-08: per-glyph slot routing (e.g. theme.success.fg for `●`) is
  # DEFERRED — the row text is rendered as a single text node with
  # theme.primary.fg so the right-align math stays simple. If a later phase
  # wants differentiated glyph colors, nav_row/3 can compose multiple
  # text nodes per row; positioned-render tests in Plan 03 still hold
  # because the per-element `x + display_width(text) <= width` assertion
  # shape is unchanged.
  @main_menu_commands [
    %{key: "B", label: "Boards", glyph: "●", kind: :destination, visibility: :always},
    %{key: "C", label: "Compose", glyph: "✎", kind: :destination, visibility: :always},
    %{key: "A", label: "Account", glyph: "◇", kind: :destination, visibility: :account},
    %{key: "M", label: "Moderation", glyph: "⚑", kind: :destination, visibility: :moderation},
    %{key: "S", label: "Sysop", glyph: "▣", kind: :destination, visibility: :sysop},
    %{key: "Q", label: "Logout", glyph: "↯", kind: :destination, visibility: :always},
    %{key: "O", label: "Oneliner", kind: :action, visibility: :authenticated},
    %{key: "H", label: "Hide oneliner", kind: :action, visibility: :hide_oneliner_policy},
    %{key: "↑/↓", label: "Select", kind: :action, visibility: :oneliners_present}
  ]

  @impl true
  @spec init(Context.t()) :: State.t()
  def init(%Context{} = context), do: State.new(context)

  @impl true
  @spec render(State.t() | nil, Context.t()) :: any()
  def render(local_state, %Context{} = context) do
    local_state = normalize_state(local_state, context)
    state = app_state_from_local(local_state, context)
    user = state.current_user
    theme = Theme.from_state(state)

    destinations = visible_destination_entries(user)
    actions = visible_actions(state)

    inner_width = nav_panel_inner_width(state)
    menu_panel = nav_panel(destinations, theme, inner_width)
    oneliners_panel_widget = oneliners_panel(state, theme)

    # `divider_char: " "` (space) — both panels render their own `│` borders, so
    # a visible split-pane divider would visually collide with them (`│ │ │`).
    # Without this, the split_pane divider's character (default `"|"`) would
    # appear at column `split_x` on every row and clobber the right panel's
    # `┌─ Oneliners ─` top-border title segment (Phase 32 MENU-02). The fix
    # for the painter orientation lives in
    # `vendor/raxol/lib/raxol/ui/layout/split_pane.ex`'s `build_divider/6`;
    # passing a space here is the screen-level half of the fix and makes the
    # divider effectively transparent so panel borders supply the visual gap.
    content =
      split_pane(
        direction: :horizontal,
        ratio: {2, 3},
        min_size: 18,
        divider_char: " ",
        children: [menu_panel, oneliners_panel_widget]
      )

    ScreenFrame.render(state, %{breadcrumb_parts: ["Foglet", "Home"]}, content, actions)
  end

  @impl true
  @spec update(term(), State.t() | nil, Context.t()) :: {State.t(), [Effect.t()]}
  def update({:key, %{key: :up}}, local_state, %Context{} = context) do
    local_state = normalize_state(local_state, context)
    {State.select_delta(local_state, -1), []}
  end

  def update({:key, %{key: :down}}, local_state, %Context{} = context) do
    local_state = normalize_state(local_state, context)
    {State.select_delta(local_state, 1), []}
  end

  def update({:key, %{key: :enter}}, local_state, %Context{} = context) do
    {normalize_state(local_state, context), []}
  end

  # Phase 39 D-01/D-03/D-14: screen owns its route-entry conditional load.
  # Preserves the user-conditional semantics today encoded in App's
  # `maybe_dispatch_route_entry/3` for `:main_menu` (`app.ex:810-816`); Plan
  # 39-05 will collapse the App-side per-screen clauses into a single generic
  # dispatch, relying on this screen-side clause to decide what to load.
  def update(:on_route_enter, local_state, %Context{} = context) do
    if context.current_user do
      update(:load_oneliners, local_state, context)
    else
      {normalize_state(local_state, context), []}
    end
  end

  def update(:load_oneliners, local_state, %Context{} = context) do
    local_state = normalize_state(local_state, context)
    {%{local_state | oneliner_status: :loading}, [load_oneliners_task_effect(context)]}
  end

  def update({:key, %{key: :char, char: c}}, local_state, %Context{} = context)
      when c in ["b", "B"] do
    {normalize_state(local_state, context),
     [Effect.navigate(:board_list), load_boards_effect(context)]}
  end

  def update({:key, %{key: :char, char: c}}, local_state, %Context{} = context)
      when c in ["c", "C"] do
    {normalize_state(local_state, context),
     [
       Effect.navigate(:new_thread, %{origin: :main_menu}),
       load_boards_for_new_thread_effect(context)
     ]}
  end

  def update({:key, %{key: :char, char: c}}, local_state, %Context{} = context)
      when c in ["o", "O"] do
    local_state = normalize_state(local_state, context)

    if context.current_user do
      {State.clear_errors(local_state), [Effect.open_modal(oneliner_composer_modal())]}
    else
      {local_state, []}
    end
  end

  def update({:key, %{key: :char, char: c}}, local_state, %Context{} = context)
      when c in ["h", "H"] do
    local_state = normalize_state(local_state, context)
    app_state = app_state_from_local(local_state, context)

    case selected_hideable_oneliner(app_state) do
      %{id: id} when is_binary(id) and id != "" ->
        local_state = local_state |> State.set_pending_hide(id) |> State.clear_errors()
        {local_state, [Effect.open_modal(hide_oneliner_modal())]}

      _other ->
        {local_state, []}
    end
  end

  def update({:key, %{key: :char, char: c}}, local_state, %Context{} = context)
      when c in ["a", "A"] do
    local_state = normalize_state(local_state, context)

    if ShellVisibility.account_visible?(context.current_user) do
      {local_state, [Effect.navigate(:account)]}
    else
      {local_state, []}
    end
  end

  def update({:key, %{key: :char, char: c}}, local_state, %Context{} = context)
      when c in ["m", "M"] do
    local_state = normalize_state(local_state, context)

    if ShellVisibility.moderation_visible?(context.current_user) do
      {local_state, [Effect.navigate(:moderation)]}
    else
      {local_state, []}
    end
  end

  def update({:key, %{key: :char, char: c}}, local_state, %Context{} = context)
      when c in ["s", "S"] do
    local_state = normalize_state(local_state, context)

    if ShellVisibility.sysop_visible?(context.current_user) do
      {local_state, [Effect.navigate(:sysop)]}
    else
      {local_state, []}
    end
  end

  def update({:key, %{key: :char, char: c}}, local_state, %Context{} = context)
      when c in ["q", "Q"] do
    {normalize_state(local_state, context), [Effect.quit()]}
  end

  def update({:task_result, :load_oneliners, {:ok, entries}}, local_state, %Context{} = context)
      when is_list(entries) do
    local_state =
      local_state
      |> normalize_state(context)
      |> State.from_entries(entries)
      |> State.clear_errors()

    {local_state, []}
  end

  def update({:task_result, :load_oneliners, {:error, reason}}, local_state, %Context{} = context) do
    local_state =
      local_state
      |> normalize_state(context)
      |> State.put_errors(%{base: "Unable to load oneliners: #{inspect(reason)}"})

    {local_state, []}
  end

  def update(
        {:modal_submit, :oneliner_composer, %{body: body}},
        local_state,
        %Context{} = context
      ) do
    local_state = normalize_state(local_state, context)

    if context.current_user do
      user = context.current_user
      oneliners_mod = domain_module(context, :oneliners)

      effect =
        Effect.task(:submit_oneliner, :main_menu, fn ->
          oneliners_mod.create_entry(user, %{body: body})
        end)

      {%{State.clear_errors(local_state) | oneliner_status: :submitting}, [effect]}
    else
      {State.put_errors(local_state, %{base: "User session is not available."}),
       [Effect.open_modal(oneliner_composer_modal(%{base: "User session is not available."}))]}
    end
  end

  def update({:modal_submit, :oneliner_composer, _payload}, local_state, %Context{} = context) do
    local_state =
      local_state
      |> normalize_state(context)
      |> State.put_errors(%{body: "Enter 1-120 characters."})

    {local_state, [Effect.open_modal(oneliner_composer_modal(local_state.oneliner_errors))]}
  end

  def update(
        {:modal_submit, :hide_oneliner, %{reason: reason}},
        local_state,
        %Context{} = context
      ) do
    local_state = normalize_state(local_state, context)
    reason = reason |> to_string() |> String.trim()

    cond do
      reason == "" ->
        errors = %{reason: "Reason is required."}
        local_state = State.put_errors(local_state, errors)
        {local_state, [Effect.open_modal(hide_oneliner_modal(errors))]}

      is_nil(context.current_user) ->
        errors = %{base: "User session is not available."}
        local_state = State.put_errors(local_state, errors)
        {local_state, [Effect.open_modal(hide_oneliner_modal(errors))]}

      is_nil(local_state.pending_hide_oneliner_id) ->
        errors = %{base: "No oneliner is selected."}
        local_state = State.put_errors(local_state, errors)
        {local_state, [Effect.open_modal(hide_oneliner_modal(errors))]}

      true ->
        user = context.current_user
        entry_id = local_state.pending_hide_oneliner_id
        oneliners_mod = domain_module(context, :oneliners)

        effect =
          Effect.task(:submit_hide_oneliner, :main_menu, fn ->
            oneliners_mod.hide_entry(user, entry_id, reason)
          end)

        {%{State.clear_errors(local_state) | oneliner_status: :hiding}, [effect]}
    end
  end

  def update({:modal_submit, :hide_oneliner, _payload}, local_state, %Context{} = context) do
    errors = %{reason: "Reason is required."}

    local_state =
      local_state
      |> normalize_state(context)
      |> State.put_errors(errors)

    {local_state, [Effect.open_modal(hide_oneliner_modal(errors))]}
  end

  def update({:task_result, :submit_oneliner, result}, local_state, %Context{} = context) do
    local_state = normalize_state(local_state, context)

    case unwrap_task_result(result) do
      {:ok, _entry} ->
        {%{State.clear_errors(local_state) | oneliner_status: :loading},
         [Effect.dismiss_modal(), load_oneliners_task_effect(context)]}

      {:error, :same_user_latest_visible} ->
        errors = %{base: "Let someone else post before posting again."}
        local_state = State.put_errors(local_state, errors)
        {local_state, [Effect.open_modal(oneliner_composer_modal(errors))]}

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = body_changeset_errors(changeset)
        local_state = State.put_errors(local_state, errors)
        {local_state, [Effect.open_modal(oneliner_composer_modal(errors))]}

      {:error, reason} ->
        errors = %{base: "Unable to post oneliner: #{inspect(reason)}"}
        local_state = State.put_errors(local_state, errors)
        {local_state, [Effect.open_modal(oneliner_composer_modal(errors))]}
    end
  end

  def update({:task_result, :submit_hide_oneliner, result}, local_state, %Context{} = context) do
    local_state = normalize_state(local_state, context)

    case unwrap_task_result(result) do
      {:ok, hidden} ->
        hidden_id = entry_id(hidden) || local_state.pending_hide_oneliner_id

        local_state =
          local_state
          |> remove_oneliner(hidden_id)
          |> State.clear_pending_hide()
          |> State.clear_errors()
          |> Map.put(:oneliner_status, :idle)

        {local_state, [Effect.dismiss_modal()]}

      {:error, :forbidden} ->
        errors = %{base: "You are not allowed to hide this oneliner."}
        local_state = State.put_errors(local_state, errors)
        {local_state, [Effect.open_modal(hide_oneliner_modal(errors))]}

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = changeset_errors(changeset)
        local_state = State.put_errors(local_state, errors)
        {local_state, [Effect.open_modal(hide_oneliner_modal(errors))]}

      {:error, reason} ->
        errors = %{base: "Unable to hide oneliner: #{inspect(reason)}"}
        local_state = State.put_errors(local_state, errors)
        {local_state, [Effect.open_modal(hide_oneliner_modal(errors))]}
    end
  end

  def update(_message, local_state, %Context{} = context) do
    {normalize_state(local_state, context), []}
  end

  # --- public data layer (D-01 single-source-of-truth split) ---

  @doc """
  Returns destination entries visible to `user`, derived by filtering the
  canonical `@main_menu_commands` list for `:destination` entries whose
  `:visibility` tag passes the role gate.

  Returns `[{key, label}]` tuples in declaration order. Rendering consumes the
  same filtered descriptors internally so destination glyphs remain co-located
  with this canonical data.

  Public so tests can assert role-gating directly without going through
  `render/1` and parsing positioned text (consistent with ShellVisibility's
  public-predicate convention).
  """
  @spec visible_destinations(map() | nil) :: [{String.t(), String.t()}]
  def visible_destinations(user) do
    user
    |> visible_destination_entries()
    |> Enum.map(&{&1.key, &1.label})
  end

  @doc """
  Returns action entries visible for `state`, grouped into command-bar groups
  for `ScreenFrame.render/4`. Derived by filtering the canonical
  `@main_menu_commands` list for `:action` entries whose `:visibility` tag
  passes the role/state gate.

  Public so tests can assert action visibility directly without going through
  `render/1` (consistent with ShellVisibility's public-predicate convention).
  """
  @spec visible_actions(map()) :: [%{label: String.t(), commands: [map()]}]
  def visible_actions(state) do
    user = state.current_user

    visible =
      @main_menu_commands
      |> Enum.filter(&(&1.kind == :action and action_visible?(&1.visibility, user, state)))

    hide_oneliner = Enum.filter(visible, &(&1.key == "H")) |> Enum.map(&{&1.key, &1.label})
    oneliner_post = Enum.filter(visible, &(&1.key == "O")) |> Enum.map(&{&1.key, &1.label})
    select_oneliner = Enum.filter(visible, &(&1.key == "↑/↓")) |> Enum.map(&{&1.key, &1.label})

    [
      command_group("Actions", hide_oneliner ++ oneliner_post),
      command_group("Select", select_oneliner)
    ]
    |> Enum.reject(&(&1.commands == []))
  end

  @doc false
  @spec __nav_panel_inner_width__(map()) :: pos_integer()
  def __nav_panel_inner_width__(state), do: nav_panel_inner_width(state)

  # --- private ---

  defp normalize_state(%State{} = state, _context), do: state
  defp normalize_state(_state, %Context{} = context), do: State.new(context)

  defp app_state_from_local(%State{} = local_state, %Context{} = context) do
    %{
      current_screen: :main_menu,
      current_user: context.current_user,
      session_context: context.session_context,
      session_pid: context.session_pid,
      terminal_size: context.terminal_size || @default_terminal_size,
      route_params: context.route_params || %{},
      screen_state: %{main_menu: local_state},
      recent_oneliners: local_state.recent_oneliners,
      selected_oneliner_index: local_state.selected_oneliner_index,
      pending_hide_oneliner_id: local_state.pending_hide_oneliner_id
    }
  end

  defp oneliner_composer_modal(errors \\ %{}) do
    form =
      ModalForm.init(
        title: "Post Oneliner",
        fields: [
          %{
            name: :body,
            type: :text,
            label: "Oneliner",
            max_length: 120,
            placeholder: "120 chars max"
          }
        ],
        on_submit: &modal_submit_effect(:oneliner_composer, &1),
        on_cancel: fn -> :dismiss_modal end,
        show_footer: true
      )
      |> maybe_set_form_errors(errors)

    %Modal{type: :form, title: "Post Oneliner", message: form}
  end

  defp hide_oneliner_modal(errors \\ %{}) do
    form =
      ModalForm.init(
        title: "Hide Oneliner",
        fields: [
          %{
            name: :reason,
            type: :text,
            label: "Reason",
            placeholder: "Required",
            max_length: 240
          }
        ],
        on_submit: &modal_submit_effect(:hide_oneliner, &1),
        on_cancel: fn -> :dismiss_modal end,
        show_footer: true
      )
      |> maybe_set_form_errors(errors)

    %Modal{type: :form, title: "Hide Oneliner", message: form}
  end

  defp maybe_set_form_errors(%ModalForm{} = form, errors) when map_size(errors) == 0, do: form

  defp maybe_set_form_errors(%ModalForm{} = form, errors) do
    form
    |> ModalForm.set_errors(errors)
    |> ModalForm.set_submit_state({:error, summarize_form_errors(errors)})
  end

  defp summarize_form_errors(errors) when is_map(errors) do
    errors
    |> Map.values()
    |> Enum.find("Validation error.", &is_binary/1)
  end

  defp load_boards_effect(%Context{} = context) do
    user = context.current_user
    boards_mod = domain_module(context, :boards)

    Effect.task(:load_boards, :board_list, fn ->
      boards_mod.board_directory_for(user)
    end)
  end

  defp load_boards_for_new_thread_effect(_context) do
    Effect.session({:dispatch, {:load_boards_for_new_thread}})
  end

  defp load_oneliners_task_effect(%Context{} = context) do
    oneliners_mod = domain_module(context, :oneliners)

    Effect.task(:load_oneliners, :main_menu, fn ->
      oneliners_mod.list_recent_visible(@oneliner_display_limit)
    end)
  end

  defp domain_module(%Context{domain: domain}, key) when is_map(domain) do
    case Map.get(domain, key) do
      module when is_atom(module) and not is_nil(module) -> module
      _other -> default_domain_module(key)
    end
  end

  defp default_domain_module(:oneliners), do: Foglet.Oneliners
  defp default_domain_module(:boards), do: Foglet.Boards

  defp modal_submit_effect(kind, payload), do: Effect.modal_submit(:main_menu, kind, payload)

  defp unwrap_task_result({:ok, {:ok, value}}), do: {:ok, value}
  defp unwrap_task_result({:ok, {:error, reason}}), do: {:error, reason}
  defp unwrap_task_result({:ok, value}), do: {:ok, value}
  defp unwrap_task_result({:error, reason}), do: {:error, reason}
  defp unwrap_task_result(other), do: {:error, other}

  defp remove_oneliner(%State{} = state, hidden_id) do
    recent_oneliners =
      Enum.reject(state.recent_oneliners || [], fn entry ->
        entry_id(entry) == hidden_id
      end)

    state
    |> State.from_entries(recent_oneliners)
    |> State.clamp_selection()
  end

  defp entry_id(%{} = entry), do: Map.get(entry, :id) || Map.get(entry, "id")
  defp entry_id(_other), do: nil

  defp body_changeset_errors(%Ecto.Changeset{} = changeset) do
    errors = changeset_errors(changeset)

    if Map.has_key?(errors, :body) do
      %{body: "Enter 1-120 characters."}
    else
      %{base: "Enter 1-120 characters."}
    end
  end

  defp changeset_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.into(%{}, fn {field, messages} -> {field, Enum.join(messages, ", ")} end)
  end

  defp visible_destination_entries(user) do
    @main_menu_commands
    |> Enum.filter(&(&1.kind == :destination and destination_visible?(&1.visibility, user)))
  end

  @spec destination_visible?(atom(), map() | nil) :: boolean()
  defp destination_visible?(:always, _user), do: true
  defp destination_visible?(:account, user), do: ShellVisibility.account_visible?(user)
  defp destination_visible?(:moderation, user), do: ShellVisibility.moderation_visible?(user)
  defp destination_visible?(:sysop, user), do: ShellVisibility.sysop_visible?(user)

  @spec action_visible?(atom(), map() | nil, map()) :: boolean()
  defp action_visible?(:authenticated, user, _state), do: not is_nil(user)

  defp action_visible?(:hide_oneliner_policy, _user, state) do
    not is_nil(selected_hideable_oneliner(state))
  end

  defp action_visible?(:oneliners_present, _user, state) do
    visible_oneliners(state) != []
  end

  defp command_group(label, keys) do
    %{
      label: label,
      commands:
        Enum.map(keys, fn {key, label} ->
          %{key: key, label: label, priority: command_priority(key)}
        end)
    }
  end

  defp command_priority("H"), do: -10
  defp command_priority("O"), do: 30
  defp command_priority(_key), do: 20

  @spec nav_panel_inner_width(map()) :: pos_integer()
  defp nav_panel_inner_width(state) do
    outer_width =
      case Map.get(state, :terminal_size) do
        {w, _h} when is_integer(w) and w > 0 -> w
        _ -> 80
      end

    # Match `<panel_width_budget>` math: outer chrome 4 cols, split ratio {2,3},
    # box border 2 cols. Floor at @nav_panel_min_inner_width.
    chrome_outer = 4
    left_alloc = div((outer_width - chrome_outer) * 2, 5)
    box_border = 2
    max(left_alloc - box_border, @nav_panel_min_inner_width)
  end

  # Note: Raxol's `:panel` measure_panel/2 shrinks the panel to
  # `children_size + double_border` unless `:width`/`:height` are explicitly
  # set (vendor/raxol/.../panels.ex:171-201). Without explicit size attrs the
  # panel will not fill the split_pane allocation, leaving the title segment
  # truncated and the right border drawn at the children-measured edge instead
  # of the chrome-allocated edge. We pass sentinel large values; `apply_constraints/2`
  # clamps to `available_space.width`/`height`, so the panel fills the pane.
  defp nav_panel(destinations, theme, inner_width) do
    %{
      type: :panel,
      attrs: %{
        title: "Navigation",
        title_attrs: %{fg: theme.title.fg},
        border: :single,
        border_fg: theme.border.fg,
        width: 9999,
        height: 9999
      },
      children: [
        column style: %{gap: 0} do
          Enum.map(destinations, &nav_row(&1, theme, inner_width))
        end
      ]
    }
  end

  # Multi-node row composition (D-06, MENU-03):
  # - Leading text node carries `theme.primary.fg` and includes the one-column
  #   inner indent (D-09, MENU-04), the destination glyph, the label, and the
  #   right-align padding.
  # - Trailing text node carries `theme.accent.fg` and renders the bracketed
  #   key token `[X]` (D-08, D-10 — color only, no style).
  # Width budget at 64x22 (inner_width = 20):
  #   indent(1) + glyph(1) + space(1) + "Moderation"(10) + "[M]"(3) = 16,
  #   leaving 4 cols of trailing padding.
  defp nav_row(%{key: key, label: label, glyph: glyph}, theme, inner_width) do
    indent = " "
    bracketed_key = "[" <> key <> "]"

    prefix_text = indent <> glyph <> " " <> label
    prefix_width = TextWidth.display_width(prefix_text)
    bracketed_key_width = TextWidth.display_width(bracketed_key)

    padding_width = max(inner_width - prefix_width - bracketed_key_width, 1)
    padding = TextWidth.pad_trailing("", padding_width)

    # NOTE: must pass an explicit opts arg (`[]`) so the `Raxol.Core.Renderer.View.row/2`
    # MACRO is invoked. Calling `row do ... end` without an opts arg matches the
    # `row/1` FUNCTION instead, which silently drops the do-block contents and
    # returns a flex with `children: []` (vendor/raxol/lib/raxol/core/renderer/view.ex
    # line 87 vs. line 92).
    row [] do
      [
        text(prefix_text <> padding, fg: theme.primary.fg),
        text(bracketed_key, fg: theme.accent.fg)
      ]
    end
  end

  defp oneliners_panel(state, theme) do
    %{
      type: :panel,
      attrs: %{
        title: "Oneliners",
        title_attrs: %{fg: theme.title.fg},
        border: :single,
        border_fg: theme.border.fg,
        width: 9999,
        height: 9999
      },
      children: [
        column style: %{gap: 0} do
          oneliner_rows(state, theme)
        end
      ]
    }
  end

  defp oneliner_rows(state, theme) do
    entries = visible_oneliners(state)
    selected_index = selected_oneliner_index(state, entries)

    case entries do
      [] ->
        [text("No oneliners yet.", fg: theme.primary.fg)]

      entries ->
        entries
        |> Enum.with_index()
        |> Enum.map(fn {entry, index} ->
          marker = if index == selected_index, do: "> ", else: "  "
          text(marker <> oneliner_row(entry), fg: theme.primary.fg)
        end)
    end
  end

  defp oneliner_row(entry) do
    handle =
      entry
      |> Map.get(:user)
      |> user_handle()
      |> clip(@oneliner_handle_limit)

    body =
      entry
      |> Map.get(:body, "")
      |> to_string()
      |> single_line()
      |> clip(@oneliner_body_limit)

    "@#{handle}  #{body}"
  end

  defp selected_hideable_oneliner(state) do
    entries = visible_oneliners(state)
    selected_index = selected_oneliner_index(state, entries)
    entry = Enum.at(entries, selected_index)

    if hideable_oneliner?(state.current_user, entry), do: entry
  end

  defp hideable_oneliner?(user, %{id: id}) when is_binary(id) and id != "" do
    Bodyguard.permit?(Authorization, :hide_oneliner, user, :site)
  end

  defp hideable_oneliner?(_user, _entry), do: false

  defp visible_oneliners(state) do
    state
    |> Map.get(:recent_oneliners, [])
    |> Kernel.||([])
    |> Enum.take(@oneliner_display_limit)
  end

  defp selected_oneliner_index(_state, []), do: 0

  defp selected_oneliner_index(state, entries) do
    state
    |> Map.get(:selected_oneliner_index, 0)
    |> normalize_index()
    |> clamp(0, length(entries) - 1)
  end

  defp normalize_index(index) when is_integer(index), do: index
  defp normalize_index(_other), do: 0

  defp clamp(value, lower, upper) do
    value
    |> Kernel.max(lower)
    |> Kernel.min(upper)
  end

  defp user_handle(nil), do: "unknown"

  defp user_handle(user) do
    user
    |> Map.get(:handle, "unknown")
    |> case do
      handle when is_binary(handle) and handle != "" -> handle
      _other -> "unknown"
    end
  end

  defp single_line(value) do
    value
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp clip(value, limit) do
    TextWidth.slice_to_width(value, limit)
  end
end
