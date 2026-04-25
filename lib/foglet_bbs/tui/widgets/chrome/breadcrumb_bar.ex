defmodule Foglet.TUI.Widgets.Chrome.BreadcrumbBar do
  @moduledoc """
  Shared Chrome V2 breadcrumb formatter for Foglet TUI screens.

  Implements Phase 18 decisions D-04, D-05, D-06, D-12, D-13, and D-16:
  screen paths are derived centrally from existing state, formatting is shared,
  display-width truncation delegates to `Foglet.TUI.TextWidth`, and render
  styles are routed through the explicit theme argument.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme

  @root "Foglet"
  @separator " ▸ "
  @ascii_separator " > "

  @account_tabs ["Profile", "Prefs", "SSH Keys", "Invites"]
  @moderation_tabs ["Queue", "Oneliners", "Invites"]
  @sysop_tabs ["Overview", "Users", "Boards", "Config", "Invites"]

  @doc """
  Returns the breadcrumb path for a TUI state map.
  """
  @spec parts_for(map()) :: [String.t()]
  def parts_for(state) when is_map(state) do
    state
    |> parts_for_screen(screen(state))
    |> normalize_parts()
  end

  def parts_for(_state), do: [@root]

  @doc """
  Formats breadcrumb parts with the default Unicode separator or ASCII fallback.
  """
  @spec format([term()], keyword()) :: String.t()
  def format(parts, opts \\ []) when is_list(parts) do
    separator = if Keyword.get(opts, :ascii?, false), do: @ascii_separator, else: @separator
    formatted = parts |> normalize_parts() |> Enum.join(separator)

    case Keyword.get(opts, :width) do
      width when is_integer(width) -> TextWidth.truncate(formatted, width)
      _ -> formatted
    end
  end

  @doc """
  Renders the breadcrumb using the explicit theme.
  """
  @spec render(Theme.t(), [term()] | map(), keyword()) :: any()
  def render(%Theme{} = theme, parts_or_state, opts \\ []) do
    parts = if is_list(parts_or_state), do: parts_or_state, else: parts_for(parts_or_state)
    content = format(parts, opts)
    slot = breadcrumb_slot(theme)

    text(content,
      fg: Map.get(slot, :fg),
      bg: Map.get(slot, :bg),
      style: Map.get(slot, :style, [])
    )
  end

  defp parts_for_screen(_state, :login), do: [@root, "Login"]
  defp parts_for_screen(_state, :main_menu), do: [@root, "Home"]
  defp parts_for_screen(_state, :board_list), do: [@root, "Boards"]
  defp parts_for_screen(state, :thread_list), do: [@root, "Boards", board_name(state)]
  defp parts_for_screen(state, :post_reader), do: [@root, board_name(state), thread_title(state)]
  defp parts_for_screen(state, :new_thread), do: [@root, board_name(state), "New Thread"]
  defp parts_for_screen(state, :post_composer), do: [@root, board_name(state), "Reply"]
  defp parts_for_screen(state, :account), do: [@root, "Account", active_tab(state, :account)]

  defp parts_for_screen(state, :moderation),
    do: [@root, "Moderation", active_tab(state, :moderation)]

  defp parts_for_screen(state, :sysop), do: [@root, "Sysop", active_tab(state, :sysop)]
  defp parts_for_screen(_state, _screen), do: [@root]

  defp normalize_parts(parts) do
    parts
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [@root | _] = rooted -> rooted
      [] -> [@root]
      unrooted -> [@root | unrooted]
    end
  end

  defp screen(state), do: Map.get(state, :current_screen)

  defp board_name(state) do
    state
    |> Map.get(:current_board, %{})
    |> Map.get(:name, "Boards")
  end

  defp thread_title(state) do
    state
    |> Map.get(:current_thread, %{})
    |> Map.get(:title, "Thread")
  end

  defp active_tab(state, screen) do
    tabs = tabs_for(screen)

    state
    |> screen_state_for(screen)
    |> active_tab_index()
    |> then(fn
      index when is_integer(index) -> Enum.at(tabs, index)
      _ -> nil
    end)
  end

  defp tabs_for(:account), do: @account_tabs
  defp tabs_for(:moderation), do: @moderation_tabs
  defp tabs_for(:sysop), do: @sysop_tabs

  defp screen_state_for(state, screen) do
    state
    |> Map.get(:screen_state, %{})
    |> Map.get(screen, %{})
  end

  defp active_tab_index(screen_state) do
    cond do
      is_integer(Map.get(screen_state, :active_tab)) ->
        Map.get(screen_state, :active_tab)

      is_integer(Map.get(screen_state, :active_tab_index)) ->
        Map.get(screen_state, :active_tab_index)

      true ->
        nil
    end
  end

  defp breadcrumb_slot(theme) do
    case theme.title do
      empty when empty == %{} -> theme.status_bar
      title -> title
    end
  end
end
