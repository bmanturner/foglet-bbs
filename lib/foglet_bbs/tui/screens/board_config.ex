defmodule Foglet.TUI.Screens.BoardConfig do
  @moduledoc "Operator-only board feed CONFIG tab."

  alias Foglet.BoardFeeds
  alias Foglet.TUI.Context
  import Raxol.Core.Renderer.View

  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{
            status: :idle | :loading | :loaded,
            feeds: list(),
            mode: :list | :add | :ttl,
            input: String.t(),
            ttl_input: String.t(),
            selected_index: non_neg_integer(),
            message: String.t() | nil
          }
    defstruct status: :idle,
              feeds: [],
              mode: :list,
              input: "",
              ttl_input: "3600",
              selected_index: 0,
              message: nil
  end

  def init(_context), do: %State{}

  def load_effects(%State{} = state, %Context{} = context) do
    board_id = board_id(context)
    actor = context.current_user

    effect =
      Foglet.TUI.Effect.task(:load_board_feed_config, :thread_list, fn ->
        BoardFeeds.list_feeds(actor, board_id)
      end)

    {%{state | status: :loading}, [effect]}
  end

  def update({:task_result, :load_board_feed_config, feeds_result}, %State{} = state, _context),
    do: {%{state | status: :loaded, feeds: unwrap_list_result(feeds_result)}, []}

  def update({:task_result, :add_board_feed, {:ok, _feed}}, %State{} = state, context) do
    state = %{state | mode: :list, input: "", message: "Feed validated and added."}
    load_effects(state, context)
  end

  def update({:task_result, :add_board_feed, {:error, reason}}, %State{} = state, _context),
    do: {%{state | message: "Feed rejected: #{inspect(reason)}"}, []}

  def update({:task_result, :refresh_board_feeds, result}, %State{} = state, context) do
    state = %{state | message: "Refresh complete: #{inspect(result)}"}
    load_effects(state, context)
  end

  def update({:task_result, :update_feed_ttl, {:ok, _feed}}, %State{} = state, context) do
    state = %{state | mode: :list, message: "TTL saved for selected feed."}
    load_effects(state, context)
  end

  def update({:task_result, :update_feed_ttl, {:error, reason}}, %State{} = state, _context),
    do: {%{state | message: "TTL rejected: #{inspect(reason)}"}, []}

  def update({:key, %{key: :char, char: c}}, %State{mode: :add} = state, _context)
      when byte_size(c) == 1 do
    {%{state | input: state.input <> c}, []}
  end

  def update({:key, %{key: :backspace}}, %State{mode: :add} = state, _context),
    do: {%{state | input: drop_last(state.input)}, []}

  def update({:key, %{key: :enter}}, %State{mode: :add} = state, context) do
    board_id = board_id(context)
    actor = context.current_user
    url = String.trim(state.input)

    effect =
      Foglet.TUI.Effect.task(:add_board_feed, :thread_list, fn ->
        BoardFeeds.create_feed(actor, board_id, %{url: url, cache_ttl_seconds: parse_ttl(state)})
      end)

    {%{state | message: "Validating feed…"}, [effect]}
  end

  def update({:key, %{key: :escape}}, %State{} = state, _context),
    do: {%{state | mode: :list, message: nil}, []}

  def update({:key, %{key: :char, char: c}}, %State{mode: :ttl} = state, _context)
      when c in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"] do
    {%{state | ttl_input: state.ttl_input <> c}, []}
  end

  def update({:key, %{key: :backspace}}, %State{mode: :ttl} = state, _context),
    do: {%{state | ttl_input: drop_last(state.ttl_input)}, []}

  def update({:key, %{key: :enter}}, %State{mode: :ttl, feeds: []} = state, _context),
    do:
      {%{state | mode: :list, message: "Default TTL for next feed set to #{parse_ttl(state)}s"},
       []}

  def update({:key, %{key: :enter}}, %State{mode: :ttl} = state, context) do
    actor = context.current_user
    ttl = parse_ttl(state)
    feed = selected_feed(state)

    effect =
      Foglet.TUI.Effect.task(:update_feed_ttl, :thread_list, fn ->
        BoardFeeds.update_feed_ttl(actor, Map.fetch!(feed, :id), ttl)
      end)

    {%{state | message: "Saving TTL for selected feed…"}, [effect]}
  end

  def update({:key, %{key: :down}}, %State{mode: :list} = state, _context),
    do:
      {%{state | selected_index: min(state.selected_index + 1, max(length(state.feeds) - 1, 0))},
       []}

  def update({:key, %{key: :up}}, %State{mode: :list} = state, _context),
    do: {%{state | selected_index: max(state.selected_index - 1, 0)}, []}

  def update({:key, %{key: :char, char: c}}, %State{mode: :list} = state, _context)
      when c in ["a", "A"] do
    {%{
       state
       | mode: :add,
         input: "",
         message: "Enter RSS/Atom URL, Enter to validate/save, Esc to cancel."
     }, []}
  end

  def update({:key, %{key: :char, char: c}}, %State{mode: :list} = state, _context)
      when c in ["t", "T"] do
    {%{
       state
       | mode: :ttl,
         ttl_input: Integer.to_string(selected_ttl(state)),
         message: ttl_prompt(state)
     }, []}
  end

  def update({:key, %{key: :char, char: c}}, %State{mode: :list} = state, context)
      when c in ["r", "R"] do
    board_id = board_id(context)
    actor = context.current_user

    effect =
      Foglet.TUI.Effect.task(:refresh_board_feeds, :thread_list, fn ->
        BoardFeeds.refresh_board(actor, board_id, force: true)
      end)

    {%{state | message: "Refreshing enabled feeds…"}, [effect]}
  end

  def update(_msg, %State{} = state, _context), do: {state, []}

  def render(%State{status: :loading}, _context, theme),
    do: text("Loading feed CONFIG…", fg: theme.dim.fg)

  def render(%State{} = state, _context, theme) do
    feed_rows = feed_rows(state, theme)

    column style: %{gap: 1} do
      [
        text("Feed CONFIG", fg: theme.accent.fg, style: [:bold]),
        text("Authorized operators can add validated RSS/Atom feeds, refresh cache, and set TTL.",
          fg: theme.dim.fg
        ),
        render_mode(state, theme)
        | feed_rows
      ]
    end
  end

  def keybar_groups(%State{mode: :add}, _context), do: input_keybar("Add feed", "Save/validate")
  def keybar_groups(%State{mode: :ttl}, _context), do: input_keybar("TTL", "Save")

  def keybar_groups(_state, _context),
    do: [
      %{
        label: "Config",
        commands: [
          %{key: "↑/↓", label: "Select", priority: 9},
          %{key: "A", label: "Add feed", priority: 10},
          %{key: "T", label: "Edit selected TTL", priority: 11},
          %{key: "R", label: "Refresh", priority: 12},
          %{key: "Esc", label: "Cancel", priority: 20}
        ]
      }
    ]

  defp render_mode(%State{mode: :add} = state, theme),
    do: text("URL: " <> state.input <> "▌", fg: theme.primary.fg)

  defp render_mode(%State{mode: :ttl} = state, theme),
    do: text(ttl_prompt(state) <> " " <> state.ttl_input <> "▌", fg: theme.primary.fg)

  defp render_mode(%State{message: message}, theme) when is_binary(message),
    do: text(message, fg: theme.dim.fg)

  defp render_mode(_state, theme), do: text("A Add  T TTL  R Refresh", fg: theme.dim.fg)

  defp feed_rows(%State{feeds: []}, theme),
    do: [text("No feeds configured. Press A to add and validate a feed URL.", fg: theme.dim.fg)]

  defp feed_rows(%State{} = state, theme) do
    state.feeds
    |> Enum.with_index()
    |> Enum.map(fn {feed, index} -> feed_row(feed, index == state.selected_index, theme) end)
  end

  defp feed_row(feed, selected?, theme) do
    title = Map.get(feed, :title) || Map.get(feed, :url) || "feed"
    ttl = Map.get(feed, :cache_ttl_seconds) || 0
    status = if Map.get(feed, :last_error), do: "error", else: "ok"
    marker = if selected?, do: "▌", else: "•"
    text("#{marker} #{title}  ttl=#{ttl}s  #{status}", fg: theme.primary.fg)
  end

  defp input_keybar(label, enter_label),
    do: [
      %{
        label: label,
        commands: [
          %{key: "Enter", label: enter_label, priority: 5},
          %{key: "Backspace", label: "Delete", priority: 6},
          %{key: "Esc", label: "Cancel", priority: 7}
        ]
      }
    ]

  defp selected_feed(%State{feeds: []}), do: nil

  defp selected_feed(%State{} = state),
    do: Enum.at(state.feeds, state.selected_index) || List.first(state.feeds)

  defp selected_ttl(%State{feeds: []} = state), do: parse_ttl(state)

  defp selected_ttl(%State{} = state),
    do: Map.get(selected_feed(state), :cache_ttl_seconds) || parse_ttl(state)

  defp ttl_prompt(%State{feeds: []}), do: "Default TTL seconds for next feed:"

  defp ttl_prompt(%State{} = state) do
    feed = selected_feed(state)
    title = Map.get(feed || %{}, :title) || Map.get(feed || %{}, :url) || "selected feed"
    "TTL seconds for #{title}:"
  end

  defp unwrap_list_result({:ok, values}) when is_list(values), do: values
  defp unwrap_list_result(values) when is_list(values), do: values
  defp unwrap_list_result(_other), do: []

  defp board_id(%Context{route_params: params}),
    do:
      Map.get(params, :board_id) || Map.get(params, "board_id") ||
        (Map.get(params, :board) || %{}) |> Map.get(:id)

  defp drop_last(""), do: ""
  defp drop_last(value), do: String.slice(value, 0, max(String.length(value) - 1, 0))

  defp parse_ttl(%State{ttl_input: value}) do
    case Integer.parse(value || "") do
      {ttl, ""} -> ttl |> max(300) |> min(86_400)
      _ -> 3600
    end
  end
end
