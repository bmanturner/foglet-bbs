defmodule Foglet.TUI.Screens.BoardNews do
  @moduledoc "Read-only board NEWS tab over cached RSS/Atom items."

  alias Foglet.BoardFeeds
  alias Foglet.TUI.Context
  import Raxol.Core.Renderer.View

  @wide_list_text_width 38
  @wide_status_width 38

  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{
            status: :idle | :loading | :loaded,
            items: list(),
            feeds: list(),
            selected_index: non_neg_integer(),
            view: :list | :detail,
            message: String.t() | nil
          }
    defstruct status: :idle, items: [], feeds: [], selected_index: 0, view: :list, message: nil
  end

  def init(_context), do: %State{}

  def load_effects(%State{} = state, %Context{} = context) do
    board_id = board_id(context)
    actor = context.current_user
    state = %{state | status: :loading}

    effects = [
      Foglet.TUI.Effect.task(:load_board_news, fn ->
        {BoardFeeds.list_feeds(actor, board_id), BoardFeeds.list_cached_items(actor, board_id)}
      end)
    ]

    {state, effects}
  end

  def update(
        {:task_result, :load_board_news, {:ok, {feeds_result, items_result}}},
        state,
        context
      ),
      do: update({:task_result, :load_board_news, {feeds_result, items_result}}, state, context)

  def update(
        {:task_result, :load_board_news, {feeds_result, items_result}},
        %State{} = state,
        _context
      ) do
    feeds = unwrap_list_result(feeds_result)
    items = unwrap_list_result(items_result)

    {%{state | status: :loaded, feeds: feeds, items: items, message: nil}, []}
  end

  def update({:key, %{key: :down}}, %State{} = state, _context),
    do:
      {%{state | selected_index: min(state.selected_index + 1, max(length(state.items) - 1, 0))},
       []}

  def update({:key, %{key: :up}}, %State{} = state, _context),
    do: {%{state | selected_index: max(state.selected_index - 1, 0)}, []}

  def update({:key, %{key: :enter}}, %State{items: [_ | _]} = state, _context),
    do: {%{state | view: :detail}, []}

  def update({:key, %{key: :escape}}, %State{} = state, _context),
    do: {%{state | view: :list}, []}

  def update(_msg, %State{} = state, _context), do: {state, []}

  def render(%State{status: :loading}, _context, theme),
    do: text("Loading cached NEWS…", fg: theme.dim.fg)

  def render(%State{items: []} = state, _context, theme) do
    status = feed_status(state.feeds)

    column style: %{gap: 1} do
      [text("No cached news items yet.", fg: theme.dim.fg), text(status, fg: theme.dim.fg)]
    end
  end

  def render(%State{view: :detail} = state, _context, theme) do
    item = Enum.at(state.items, state.selected_index) || hd(state.items)
    feed = (item.feed && item.feed.title) || "feed"

    column style: %{gap: 1} do
      [
        text("NEWS detail", fg: theme.accent.fg, style: [:bold]),
        text(feed <> " — " <> (Map.get(item, :title) || "Untitled"), fg: theme.primary.fg),
        text(Map.get(item, :summary) || "No summary cached.", fg: theme.dim.fg),
        text(Map.get(item, :url) || "", fg: theme.dim.fg),
        text("Esc returns to list.", fg: theme.dim.fg)
      ]
    end
  end

  def render(%State{} = state, %Context{terminal_size: {width, _height}}, theme)
      when width >= 110 do
    selected = Enum.at(state.items, state.selected_index) || hd(state.items)

    row style: %{gap: 2} do
      [
        box style: %{border: :single, padding: 1, width: 44} do
          column style: %{gap: 0} do
            [
              text("Cached board news", fg: theme.accent.fg, style: [:bold])
              | list_rows(state, theme)
            ]
          end
        end,
        box style: %{border: :single, padding: 1, flex: 1} do
          detail_lines(selected, theme, "Selected entry")
        end
      ]
    end
  end

  def render(%State{} = state, _context, theme) do
    column style: %{gap: 0} do
      [text("Cached board news", fg: theme.accent.fg, style: [:bold]) | list_rows(state, theme)]
    end
  end

  defp list_rows(%State{} = state, theme) do
    rows =
      state.items
      |> Enum.take(8)
      |> Enum.with_index()
      |> Enum.flat_map(fn {item, idx} ->
        selected? = idx == state.selected_index
        prefix = if selected?, do: "▌ ", else: "  "
        feed = (item.feed && item.feed.title) || "feed"
        title = Map.get(item, :title) || "Untitled"
        url = Map.get(item, :url) || ""
        summary = Map.get(item, :summary) || ""

        [
          text(truncate(prefix <> feed <> " — " <> title, @wide_list_text_width),
            fg: if(selected?, do: theme.accent.fg, else: theme.primary.fg),
            style: if(selected?, do: [:bold], else: [])
          ),
          text(truncate("  " <> summary, @wide_list_text_width), fg: theme.dim.fg),
          text(truncate("  " <> url, @wide_list_text_width), fg: theme.dim.fg)
        ]
      end)

    rows ++ [text(truncate(feed_status(state.feeds), @wide_status_width), fg: theme.dim.fg)]
  end

  def keybar_groups(_state, _context),
    do: [
      %{
        label: "News",
        commands: [
          %{key: "↑/↓", label: "Select", priority: 12},
          %{key: "Enter", label: "Detail", priority: 13},
          %{key: "Esc", label: "List", priority: 14}
        ]
      }
    ]

  defp detail_lines(item, theme, heading) do
    feed = (item.feed && item.feed.title) || "feed"

    column style: %{gap: 1} do
      [
        text(heading, fg: theme.accent.fg, style: [:bold]),
        text(feed <> " — " <> (Map.get(item, :title) || "Untitled"), fg: theme.primary.fg),
        text(Map.get(item, :summary) || "No summary cached.", fg: theme.dim.fg),
        text(Map.get(item, :url) || "", fg: theme.dim.fg)
      ]
    end
  end

  defp feed_status([]), do: "No enabled feeds are cached for this board."

  defp feed_status(feeds) do
    feed_names = Enum.map_join(feeds, ", ", &(Map.get(&1, :title) || Map.get(&1, :url) || "feed"))

    errors =
      feeds
      |> Enum.filter(&Map.get(&1, :last_error))
      |> Enum.map_join("; ", fn feed ->
        name = Map.get(feed, :title) || Map.get(feed, :url) || "feed"
        "#{name} error: #{Map.get(feed, :last_error)}"
      end)

    last_success =
      feeds
      |> Enum.map(&Map.get(&1, :last_success_at))
      |> Enum.reject(&is_nil/1)
      |> Enum.max(DateTime, fn -> nil end)

    success_text = if last_success, do: " last success: #{format_time(last_success)}", else: ""
    error_text = if errors == "", do: "", else: " stale; #{errors}"

    "Feeds: #{feed_names}#{error_text}#{success_text}"
  end

  defp truncate(value, max_width) when is_binary(value) do
    if String.length(value) <= max_width do
      value
    else
      String.slice(value, 0, max(max_width - 1, 0)) <> "…"
    end
  end

  defp unwrap_list_result({:ok, values}) when is_list(values), do: values
  defp unwrap_list_result(values) when is_list(values), do: values
  defp unwrap_list_result(_other), do: []

  defp format_time(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%MZ")
  defp format_time(%NaiveDateTime{} = datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  defp format_time(other), do: to_string(other)

  defp board_id(%Context{route_params: params}),
    do:
      Map.get(params, :board_id) || Map.get(params, "board_id") ||
        (Map.get(params, :board) || %{}) |> Map.get(:id)
end
