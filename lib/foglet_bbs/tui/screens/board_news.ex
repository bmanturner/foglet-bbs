defmodule Foglet.TUI.Screens.BoardNews do
  @moduledoc "Read-only board NEWS tab over cached RSS/Atom items."

  alias Foglet.BoardFeeds
  alias Foglet.TUI.Context
  import Raxol.Core.Renderer.View

  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{
            status: :idle | :loading | :loaded,
            items: list(),
            feeds: list(),
            selected_index: non_neg_integer(),
            message: String.t() | nil
          }
    defstruct status: :idle, items: [], feeds: [], selected_index: 0, message: nil
  end

  def init(_context), do: %State{}

  def load_effects(%State{} = state, %Context{} = context) do
    board_id = board_id(context)
    actor = context.current_user
    state = %{state | status: :loading}

    effects = [
      Foglet.TUI.Effect.task(:load_board_news, {:board_news, board_id}, fn ->
        {BoardFeeds.list_feeds(actor, board_id), BoardFeeds.list_cached_items(actor, board_id)}
      end)
    ]

    {state, effects}
  end

  def update({:task_result, :load_board_news, {feeds, items}}, %State{} = state, _context) do
    {%{state | status: :loaded, feeds: feeds, items: items, message: nil}, []}
  end

  def update({:key, %{key: :down}}, %State{} = state, _context),
    do:
      {%{state | selected_index: min(state.selected_index + 1, max(length(state.items) - 1, 0))},
       []}

  def update({:key, %{key: :up}}, %State{} = state, _context),
    do: {%{state | selected_index: max(state.selected_index - 1, 0)}, []}

  def update(_msg, %State{} = state, _context), do: {state, []}

  def render(%State{status: :loading}, _context, theme),
    do: text("Loading cached NEWS…", fg: theme.dim.fg)

  def render(%State{items: []} = state, _context, theme) do
    status = feed_status(state.feeds)

    column style: %{gap: 1} do
      [text("No cached news items yet.", fg: theme.dim.fg), text(status, fg: theme.dim.fg)]
    end
  end

  def render(%State{} = state, _context, theme) do
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
          text(prefix <> feed <> " — " <> title,
            fg: if(selected?, do: theme.accent.fg, else: theme.primary.fg),
            style: if(selected?, do: [:bold], else: [])
          ),
          text("  " <> summary, fg: theme.dim.fg),
          text("  " <> url, fg: theme.dim.fg)
        ]
      end)

    column style: %{gap: 0} do
      [text("Cached board news", fg: theme.accent.fg, style: [:bold]) | rows]
    end
  end

  def keybar_groups(_state, _context),
    do: [%{label: "News", commands: [%{key: "↑/↓", label: "Select", priority: 12}]}]

  defp feed_status([]), do: "No enabled feeds are cached for this board."

  defp feed_status(feeds),
    do:
      "Feeds: " <>
        Enum.map_join(feeds, ", ", &(Map.get(&1, :title) || Map.get(&1, :url) || "feed"))

  defp board_id(%Context{route_params: params}),
    do:
      Map.get(params, :board_id) || Map.get(params, "board_id") ||
        (Map.get(params, :board) || %{}) |> Map.get(:id)
end
