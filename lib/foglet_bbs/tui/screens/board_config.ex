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
            message: String.t() | nil
          }
    defstruct status: :idle, feeds: [], message: nil
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

  def update(_msg, %State{} = state, _context), do: {state, []}

  def render(%State{status: :loading}, _context, theme),
    do: text("Loading feed CONFIG…", fg: theme.dim.fg)

  def render(%State{} = state, _context, theme) do
    feed_rows =
      if state.feeds == [],
        do: [
          text("No feeds configured. Add/validate feeds from the feed context-backed form flow.",
            fg: theme.dim.fg
          )
        ],
        else: Enum.map(state.feeds, &feed_row(&1, theme))

    column style: %{gap: 1} do
      [
        text("Feed CONFIG", fg: theme.accent.fg, style: [:bold]),
        text("Authorized operators can add validated RSS/Atom feeds, refresh cache, and set TTL.",
          fg: theme.dim.fg
        )
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
          %{key: "R", label: "Refresh", priority: 11}
        ]
      }
    ]

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
end
