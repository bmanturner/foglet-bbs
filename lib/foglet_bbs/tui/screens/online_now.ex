defmodule Foglet.TUI.Screens.OnlineNow do
  @moduledoc """
  Routed Online Now screen for authenticated session presence.

  This is intentionally a routed screen, not a modal. The current app modal
  runtime has a single modal slot and no selectable/scrollable list body or
  modal stack. Keeping Online Now as a screen preserves normal Back/Q routing
  while allowing `V` to open the existing public profile modal for the selected
  user.
  """

  @behaviour Foglet.TUI.Screen

  alias Foglet.Accounts.PublicProfile
  alias Foglet.TerminalText
  alias Foglet.TUI.{Context, Effect, Modal}
  alias Foglet.TUI.Screens.OnlineNow.State
  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame

  import Raxol.Core.Renderer.View

  @default_terminal_size {80, 24}
  @handle_limit 18
  @presence_limit 34

  @impl true
  @spec init(Context.t()) :: State.t()
  def init(%Context{}), do: State.new()

  @impl true
  @spec update(term(), State.t() | nil, Context.t()) :: {State.t(), [Effect.t()]}
  def update(:on_route_enter, local_state, %Context{} = context) do
    state = normalize_state(local_state)
    {%{state | status: :loading}, [load_online_now_effect(context)]}
  end

  def update({:task_result, :load_online_now, {:ok, rows}}, local_state, %Context{})
      when is_list(rows) do
    {State.from_rows(normalize_state(local_state), rows), []}
  end

  def update({:task_result, :load_online_now, {:error, reason}}, local_state, %Context{}) do
    {State.set_error(normalize_state(local_state), reason), []}
  end

  def update({:key, %{key: key}}, local_state, %Context{} = context)
      when key in [:up, :down] do
    state = normalize_state(local_state)
    delta = if key == :up, do: -1, else: 1
    {State.select_delta(state, delta, visible_row_limit(context)), []}
  end

  def update({:key, %{key: :char, char: c}}, local_state, %Context{} = context)
      when c in ["j", "k"] do
    state = normalize_state(local_state)
    delta = if c == "k", do: -1, else: 1
    {State.select_delta(state, delta, visible_row_limit(context)), []}
  end

  def update({:key, %{key: :char, char: c}}, local_state, %Context{})
      when c in ["q", "Q", "b", "B"] do
    {normalize_state(local_state), [Effect.navigate(:main_menu)]}
  end

  def update({:key, %{key: :escape}}, local_state, %Context{}) do
    {normalize_state(local_state), [Effect.navigate(:main_menu)]}
  end

  def update({:key, %{key: :char, char: c}}, local_state, %Context{} = context)
      when c in ["v", "V"] do
    state = normalize_state(local_state)

    case State.selected_row(state) do
      %{user: user} when is_map(user) ->
        profile = load_public_profile(user, context)
        modal = %Modal{type: :info, title: "Public Profile", message: profile}
        {state, [Effect.open_modal(modal)]}

      _other ->
        {state, []}
    end
  end

  def update(_message, local_state, %Context{}), do: {normalize_state(local_state), []}

  @impl true
  @spec render(State.t() | nil, Context.t()) :: term()
  def render(local_state, %Context{} = context) do
    state =
      normalize_state(local_state) |> State.ensure_selected_visible(visible_row_limit(context))

    theme = Theme.from_state(frame_state(context))

    ScreenFrame.render(
      frame_state(context),
      %{breadcrumb_parts: ["Foglet", "Online Now"]},
      content_body(state, context, theme),
      action_groups(state)
    )
  end

  defp content_body(%State{} = state, %Context{} = context, theme) do
    column style: %{gap: 0, padding: 1} do
      header_rows(state, theme) ++ body_rows(state, context, theme)
    end
  end

  defp header_rows(%State{status: :error, last_error: error}, theme) do
    [
      text(error || "Unable to load online users.", fg: theme.error.fg),
      text("", fg: theme.dim.fg)
    ]
  end

  defp header_rows(%State{status: :loading}, theme) do
    [text("Loading authenticated sessions…", fg: theme.dim.fg), text("", fg: theme.dim.fg)]
  end

  defp header_rows(%State{rows: rows}, theme) do
    label =
      "#{length(rows)} authenticated #{if length(rows) == 1, do: "user", else: "users"} online"

    [text(label, fg: theme.dim.fg), text("", fg: theme.dim.fg)]
  end

  defp body_rows(%State{rows: []}, _context, theme) do
    [text("No authenticated users are online.", fg: theme.primary.fg)]
  end

  defp body_rows(%State{} = state, %Context{} = context, theme) do
    row_width = row_width(context)

    state
    |> State.visible_rows(visible_row_limit(context))
    |> Enum.map(fn {row, index} ->
      marker = if index == state.selected_index, do: "> ", else: "  "
      fg = if index == state.selected_index, do: theme.accent.fg, else: theme.primary.fg
      text(marker <> format_row(row, row_width), fg: fg)
    end)
  end

  defp format_row(row, row_width) do
    handle =
      row |> Map.get(:handle, "unknown") |> sanitize() |> TextWidth.slice_to_width(@handle_limit)

    role = role_badge(Map.get(row, :role))

    presence =
      row
      |> Map.get(:presence_label, "Online")
      |> sanitize()
      |> TextWidth.slice_to_width(@presence_limit)

    left = "@#{handle}" <> role

    padding =
      TextWidth.pad_trailing(
        "",
        max(row_width - TextWidth.display_width(left) - TextWidth.display_width(presence), 2)
      )

    TextWidth.slice_to_width(left <> padding <> presence, row_width)
  end

  defp role_badge(:sysop), do: " [SYSOP]"
  defp role_badge(:mod), do: " [MOD]"
  defp role_badge(_role), do: ""

  defp action_groups(%State{rows: []}) do
    [%{label: "Navigation", commands: [%{key: "Q", label: "Back", priority: 0}]}]
  end

  defp action_groups(%State{}) do
    [
      %{label: "Navigation", commands: [%{key: "Q", label: "Back", priority: 0}]},
      %{
        label: "Actions",
        commands: [
          %{key: "V", label: "Profile", priority: 5},
          %{key: "↑/↓", label: "Select", priority: 10}
        ]
      }
    ]
  end

  defp load_online_now_effect(%Context{} = context) do
    online_now_mod = domain_module(context, :online_now, Foglet.Sessions.OnlineNow)

    Effect.task(:load_online_now, :online_now, fn ->
      online_now_mod.list(current_user: context.current_user)
    end)
  end

  defp load_public_profile(user, %Context{} = context) when is_map(user) do
    profile_mod = domain_module(context, :public_profile, PublicProfile)

    with user_id when is_binary(user_id) <- Map.get(user, :id) || Map.get(user, "id"),
         {:ok, %PublicProfile{} = profile} <- profile_mod.load(user_id) do
      profile
    else
      _ -> PublicProfile.from_user(user)
    end
  end

  defp domain_module(%Context{domain: domain}, key, default) when is_map(domain) do
    case Map.get(domain, key) do
      module when is_atom(module) and not is_nil(module) -> module
      _other -> default
    end
  end

  defp domain_module(%Context{}, _key, default), do: default

  defp normalize_state(%State{} = state), do: state
  defp normalize_state(_other), do: State.new()

  defp frame_state(%Context{} = context) do
    %{
      current_screen: :online_now,
      current_user: context.current_user,
      session_context: context.session_context,
      session_pid: context.session_pid,
      terminal_size: context.terminal_size || @default_terminal_size,
      route_params: context.route_params || %{},
      screen_state: %{}
    }
  end

  defp visible_row_limit(%Context{terminal_size: {_w, h}}) when is_integer(h), do: max(h - 8, 3)
  defp visible_row_limit(%Context{}), do: 10

  defp row_width(%Context{terminal_size: {w, _h}}) when is_integer(w), do: max(w - 8, 24)
  defp row_width(%Context{}), do: 72

  defp sanitize(value) do
    value
    |> to_string()
    |> TerminalText.sanitize_plain_text()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
