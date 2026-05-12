defmodule Foglet.TUI.App.PubSubRouter do
  @moduledoc """
  Forwards live PubSub broadcasts to the active screen reducer.

  Messages arrive at `Foglet.TUI.App.update/2` as 3-tuples like
  `{topic, id_or_event, payload}` after the PubSubForwarder subscription
  delivers them. Screens that care (e.g., `BoardList` for `:board_activity`,
  `BoardScreen` for `:board_chat`) match the message in their own `update/3`;
  screens that don't simply hit their catch-all and no-op.

  This module exists so adding a new live-broadcast topic is a one-line edit
  to `@routable_topics` rather than another `do_update` clause in `app.ex`.

  ## Adding a new topic

  Add the atom to `@routable_topics` and document why screens care about it.
  The module attribute is the canonical list — `is_routable/1` and `topics/0`
  both derive from it.

  ## Topics

    * `:board_activity` — Phase 39 R8: BoardList re-renders unread/last-post
      timestamps.
    * `:thread_activity` — Phase 39 R8: PostReader appends new replies live.
    * `:board_screen` — FOG-253 / FOG-250: BoardScreen updates its
      `2 CHAT (#)` presence counter when other users join/leave.
    * `:board_chat` — FOG-284 / FOG-254/256: BoardScreen appends live chat
      messages to the chat tab transcript. Without this clause the sender's
      own session never sees its post.
    * `:notifications` — durable inbox/Main Menu unread-refresh broadcasts.
  """

  alias Foglet.TUI.App.Routing

  @type topic ::
          :board_activity
          | :thread_activity
          | :board_screen
          | :board_chat
          | :notifications

  @routable_topics [:board_activity, :thread_activity, :board_screen, :board_chat, :notifications]

  @doc """
  Guard-safe predicate for "is this a 3-tuple broadcast we forward to the
  active screen?". Use as a guard on `do_update/2` clauses in `App`.
  """
  defguard is_routable(msg)
           when is_tuple(msg) and tuple_size(msg) == 3 and
                  elem(msg, 0) in @routable_topics

  @doc "Returns the canonical list of routable broadcast topics."
  @spec topics() :: nonempty_list(topic())
  def topics, do: @routable_topics

  @doc """
  Forwards a broadcast to interested screen reducers.

  Most PubSub broadcasts are active-screen concerns. Notification broadcasts are
  different: the focused Inbox must reload its list, while the cached Main Menu
  state must also refresh its unread badge so returning home does not depend on
  navigation-time reloads.

  Caller is `Foglet.TUI.App.do_update/2`, which only invokes us under the
  `is_routable/1` guard; we don't reassert the App struct here to avoid a
  compile-time cycle (`App` requires this module for the defguard, so this
  module cannot reference `App.t/0` in its specs).
  """
  @spec forward(struct(), tuple()) :: {struct(), [Raxol.Core.Runtime.Command.t()]}
  def forward(state, {:notifications, event, payload} = msg) do
    state = store_live_unread_count(state, event, payload)
    current_key = Routing.screen_key(Routing.current_route(state))

    [:main_menu, current_key]
    |> Enum.uniq()
    |> Enum.reduce({state, []}, fn key, {acc_state, acc_commands} ->
      {next_state, commands} = Routing.route_screen_update(acc_state, key, msg)
      {next_state, acc_commands ++ commands}
    end)
  end

  def forward(state, msg) when is_routable(msg) do
    Routing.route_screen_update(state, Routing.screen_key(Routing.current_route(state)), msg)
  end

  defp store_live_unread_count(state, :created, payload) do
    if unread_created_payload?(payload) do
      Map.update(state, :unread_count, 1, &(&1 + 1))
    else
      state
    end
  end

  defp store_live_unread_count(state, :read, _payload) do
    Map.update(state, :unread_count, 0, &max(&1 - 1, 0))
  end

  defp store_live_unread_count(state, :all_read, _payload) do
    Map.put(state, :unread_count, 0)
  end

  defp store_live_unread_count(state, _event, _payload), do: state

  defp unread_created_payload?(%{read_at: nil}), do: true
  defp unread_created_payload?(%{read_at: %DateTime{}}), do: false
  defp unread_created_payload?(_payload), do: true
end
