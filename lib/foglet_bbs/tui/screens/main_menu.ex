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

  alias Foglet.TUI.Screens.{Account, Moderation, ShellVisibility, Sysop}
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame

  import Raxol.Core.Renderer.View

  @default_terminal_size {80, 24}

  @base_items [
    {"B", "Browse Boards"},
    {"C", "Compose New Thread"}
  ]

  @base_keys [
    {"B", "Boards"},
    {"C", "Compose"}
  ]

  @logout_item {"Q", "Logout"}
  @logout_key {"Q", "Logout"}

  @impl true
  @spec render(map()) :: any()
  def render(state) do
    user = state.current_user
    handle = user && user.handle
    theme = Theme.from_state(state)

    items = visible_menu_items(user)
    keys = visible_menu_keys(user)

    content =
      column style: %{gap: 0} do
        [text("Welcome back, #{handle || "guest"}.", fg: theme.primary.fg), text("")] ++
          Enum.map(items, fn {k, label} ->
            text("  [#{k}] #{label}", fg: theme.primary.fg)
          end)
      end

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
      {:update, %{state | current_screen: :moderation, screen_state: new_screen_state}, []}
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

    @base_items ++ account ++ moderation ++ sysop ++ [@logout_item]
  end

  defp visible_menu_keys(user) do
    account = if ShellVisibility.account_visible?(user), do: [{"A", "Account"}], else: []
    moderation = if ShellVisibility.moderation_visible?(user), do: [{"M", "Mod"}], else: []
    sysop = if ShellVisibility.sysop_visible?(user), do: [{"S", "Sysop"}], else: []

    @base_keys ++ account ++ moderation ++ sysop ++ [@logout_key]
  end
end
