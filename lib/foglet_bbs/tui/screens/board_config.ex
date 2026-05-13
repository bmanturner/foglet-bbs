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
      Foglet.TUI.Effect.task(:load_board_feed_config, {:board_config, board_id}, fn ->
        BoardFeeds.list_feeds(actor, board_id)
      end)

    {%{state | status: :loading}, [effect]}
  end

  def update({:task_result, :load_board_feed_config, feeds}, %State{} = state, _context),
    do: {%{state | status: :loaded, feeds: feeds}, []}

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
      Foglet.TUI.Effect.task(:add_board_feed, {:board_config_add, board_id}, fn ->
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

  def update({:key, %{key: :enter}}, %State{mode: :ttl} = state, _context),
    do: {%{state | mode: :list, message: "TTL set for next added feed: #{parse_ttl(state)}s"}, []}

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
         ttl_input: Integer.to_string(parse_ttl(state)),
         message: "Enter TTL seconds."
     }, []}
  end

  def update({:key, %{key: :char, char: c}}, %State{mode: :list} = state, context)
      when c in ["r", "R"] do
    board_id = board_id(context)
    actor = context.current_user

    effect =
      Foglet.TUI.Effect.task(:refresh_board_feeds, {:board_config_refresh, board_id}, fn ->
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

  def keybar_groups(_state, _context),
    do: [
      %{
        label: "Config",
        commands: [
          %{key: "A", label: "Add feed", priority: 10},
          %{key: "T", label: "TTL", priority: 11},
          %{key: "R", label: "Refresh", priority: 12},
          %{key: "Esc", label: "Cancel", priority: 20}
        ]
      }
    ]

  defp render_mode(%State{mode: :add} = state, theme),
    do: text("URL: " <> state.input <> "▌", fg: theme.primary.fg)

  defp render_mode(%State{mode: :ttl} = state, theme),
    do: text("TTL seconds: " <> state.ttl_input <> "▌", fg: theme.primary.fg)

  defp render_mode(%State{message: message}, theme) when is_binary(message),
    do: text(message, fg: theme.dim.fg)

  defp render_mode(_state, theme), do: text("A Add  T TTL  R Refresh", fg: theme.dim.fg)

  defp feed_rows(%State{feeds: []}, theme),
    do: [text("No feeds configured. Press A to add and validate a feed URL.", fg: theme.dim.fg)]

  defp feed_rows(%State{} = state, theme), do: Enum.map(state.feeds, &feed_row(&1, theme))

  defp feed_row(feed, theme) do
    title = Map.get(feed, :title) || Map.get(feed, :url) || "feed"
    ttl = Map.get(feed, :cache_ttl_seconds) || 0
    status = if Map.get(feed, :last_error), do: "error", else: "ok"
    text("• #{title}  ttl=#{ttl}s  #{status}", fg: theme.primary.fg)
  end

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
