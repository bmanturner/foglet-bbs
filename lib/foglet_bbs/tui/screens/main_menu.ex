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
  @oneliner_body_limit 22

  @base_items [
    {"B", "Browse Boards"},
    {"C", "Compose New Thread"}
  ]

  @base_keys [
    {"B", "Boards"},
    {"C", "Compose"}
  ]

  @oneliner_item {"O", "Post Oneliner"}
  @oneliner_key {"O", "Oneliner"}
  @logout_item {"Q", "Logout"}
  @logout_key {"Q", "Logout"}

  @impl true
  @spec render(map()) :: any()
  def render(state) do
    user = state.current_user
    handle = user && user.handle
    theme = Theme.from_state(state)

    items = visible_menu_items(user)
    keys = visible_menu_keys(state)

    menu_panel =
      column style: %{gap: 0} do
        [text("Welcome back, #{handle || "guest"}.", fg: theme.primary.fg), text("")] ++
          Enum.map(items, fn {k, label} ->
            text("  [#{k}] #{label}", fg: theme.primary.fg)
          end)
      end

    oneliners_panel =
      column style: %{gap: 0} do
        [text("Oneliners", fg: theme.primary.fg), text("")] ++ oneliner_rows(state, theme)
      end

    content =
      split_pane(
        direction: :horizontal,
        ratio: {2, 3},
        min_size: 24,
        children: [menu_panel, oneliners_panel]
      )

    ScreenFrame.render(state, "Main Menu", content, keys)
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

  # --- private ---

  defp visible_menu_items(user) do
    account = if ShellVisibility.account_visible?(user), do: [{"A", "Account"}], else: []
    moderation = if ShellVisibility.moderation_visible?(user), do: [{"M", "Moderation"}], else: []
    sysop = if ShellVisibility.sysop_visible?(user), do: [{"S", "Sysop"}], else: []
    oneliner = if user, do: [@oneliner_item], else: []

    @base_items ++ account ++ moderation ++ sysop ++ oneliner ++ [@logout_item]
  end

  defp visible_menu_keys(state) do
    user = state.current_user

    account = if ShellVisibility.account_visible?(user), do: [{"A", "Account"}], else: []
    moderation = if ShellVisibility.moderation_visible?(user), do: [{"M", "Mod"}], else: []
    sysop = if ShellVisibility.sysop_visible?(user), do: [{"S", "Sysop"}], else: []
    oneliner = if user, do: [@oneliner_key], else: []
    hide_oneliner = if selected_hideable_oneliner(state), do: [{"H", "Hide oneliner"}], else: []

    @base_keys ++ account ++ moderation ++ sysop ++ oneliner ++ hide_oneliner ++ [@logout_key]
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

  defp clamp(value, min, max) do
    value
    |> max(min)
    |> min(max)
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
