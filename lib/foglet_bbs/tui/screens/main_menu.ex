defmodule Foglet.TUI.Screens.MainMenu do
  @moduledoc """
  BBS main menu — primary screen after login (SSH-07, SSH-08).

  Phase 0 adds role-gated entries for Account (D-01 — any authenticated user),
  Moderation (D-02 — `:mod`/`:sysop`), and Sysop (D-02 — `:sysop` only), all
  driven by `Foglet.TUI.Screens.ShellVisibility` predicates to prevent drift
  between MainMenu and the shells (Security Domain mitigation).

  MainMenu remains stateless: no `screen_state[:main_menu]`.

  Menu visibility is NOT authorization (Pitfall 3) — real actor-aware authz
  arrives in Phase 1. Phase 0 shells are all read-only placeholders.

  Phase 19 (Plan 01) introduces a single canonical `@main_menu_commands`
  descriptor list with a `:kind` tag (`:destination` or `:action`). Public
  `visible_destinations/1` and `visible_actions/1` are derived by filtering this
  one list, so destinations vs. actions cannot drift (D-01 single-source-of-truth).
  """

  @behaviour Foglet.TUI.Screen

  alias Foglet.Authorization
  alias Foglet.TUI.Screens.{Account, Moderation, ShellVisibility, Sysop}
  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame

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
  @spec render(map()) :: any()
  def render(state) do
    user = state.current_user
    theme = Theme.from_state(state)

    destinations = visible_destination_entries(user)
    actions = visible_actions(state)

    inner_width = nav_panel_inner_width(state)
    menu_panel = nav_panel(destinations, theme, inner_width)
    oneliners_panel_widget = oneliners_panel(state, theme)

    content =
      split_pane(
        direction: :horizontal,
        ratio: {2, 3},
        min_size: 18,
        children: [menu_panel, oneliners_panel_widget]
      )

    ScreenFrame.render(state, "Main Menu", content, actions)
  end

  @impl true
  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  def handle_key(%{key: :char, char: c}, state) when c in ["b", "B"] do
    {:update, %{state | current_screen: :board_list}, [{:load_boards}]}
  end

  def handle_key(%{key: :char, char: c}, state) when c in ["c", "C"] do
    {w, _h} = state.terminal_size || @default_terminal_size

    ss =
      Foglet.TUI.Screens.NewThread.init_screen_state(width: w)
      |> then(&%{&1 | origin: :main_menu})

    new_screen_state = Map.put(state.screen_state, :new_thread, ss)

    {:update, %{state | current_screen: :new_thread, screen_state: new_screen_state},
     [{:load_boards_for_new_thread}]}
  end

  def handle_key(%{key: :char, char: c}, state) when c in ["o", "O"] do
    if state.current_user do
      {:update, state, [{:open_oneliner_composer}]}
    else
      :no_match
    end
  end

  def handle_key(%{key: :char, char: c}, state) when c in ["h", "H"] do
    case selected_hideable_oneliner(state) do
      %{id: id} when is_binary(id) and id != "" ->
        {:update, state, [{:open_hide_oneliner_modal, id}]}

      _other ->
        :no_match
    end
  end

  def handle_key(%{key: :up}, state) do
    update_selected_oneliner(state, -1)
  end

  def handle_key(%{key: :down}, state) do
    update_selected_oneliner(state, 1)
  end

  def handle_key(%{key: :enter}, _state), do: :no_match

  def handle_key(%{key: :char, char: c}, state) when c in ["a", "A"] do
    if ShellVisibility.account_visible?(state.current_user) do
      invites? = ShellVisibility.invites_visible?(state.current_user, state.session_context)
      ss = Account.init_screen_state(invites_visible?: invites?)
      new_screen_state = Map.put(state.screen_state, :account, ss)
      {:update, %{state | current_screen: :account, screen_state: new_screen_state}, []}
    else
      :no_match
    end
  end

  def handle_key(%{key: :char, char: c}, state) when c in ["m", "M"] do
    if ShellVisibility.moderation_visible?(state.current_user) do
      ss = Moderation.init_screen_state([])
      new_screen_state = Map.put(state.screen_state, :moderation, ss)

      {:update, %{state | current_screen: :moderation, screen_state: new_screen_state},
       [{:load_moderation_workspace}]}
    else
      :no_match
    end
  end

  def handle_key(%{key: :char, char: c}, state) when c in ["s", "S"] do
    if ShellVisibility.sysop_visible?(state.current_user) do
      ss = Sysop.init_screen_state([])
      new_screen_state = Map.put(state.screen_state, :sysop, ss)
      {:update, %{state | current_screen: :sysop, screen_state: new_screen_state}, []}
    else
      :no_match
    end
  end

  def handle_key(%{key: :char, char: c}, state) when c in ["q", "Q"] do
    {:update, state, [{:terminate, :logout}]}
  end

  def handle_key(_key, _state), do: :no_match

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

  defp nav_panel(destinations, theme, inner_width) do
    box style: %{border: :single, border_fg: theme.border.fg} do
      column style: %{gap: 0} do
        [
          text("Navigation", fg: theme.title.fg)
          | Enum.map(destinations, &nav_row(&1, theme, inner_width))
        ]
      end
    end
  end

  defp nav_row(%{key: key, label: label, glyph: glyph}, theme, inner_width) do
    prefix = glyph <> " " <> label
    prefix_width = TextWidth.display_width(prefix)
    key_width = TextWidth.display_width(key)
    padding_width = max(inner_width - prefix_width - key_width, 1)
    padding = TextWidth.pad_trailing("", padding_width)
    text(prefix <> padding <> key, fg: theme.primary.fg)
  end

  defp oneliners_panel(state, theme) do
    box style: %{border: :single, border_fg: theme.border.fg} do
      column style: %{gap: 0} do
        [text("Oneliners", fg: theme.title.fg) | oneliner_rows(state, theme)]
      end
    end
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

  defp update_selected_oneliner(state, delta) do
    entries = visible_oneliners(state)

    case entries do
      [] ->
        :no_match

      entries ->
        selected_index =
          state
          |> selected_oneliner_index(entries)
          |> Kernel.+(delta)
          |> clamp(0, length(entries) - 1)

        {:update, Map.put(state, :selected_oneliner_index, selected_index), []}
    end
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
