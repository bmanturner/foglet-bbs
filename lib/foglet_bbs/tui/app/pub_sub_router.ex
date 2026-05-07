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
  """

  alias Foglet.TUI.App.Routing

  @routable_topics [:board_activity, :thread_activity, :board_screen, :board_chat]

  @doc """
  Guard-safe predicate for "is this a 3-tuple broadcast we forward to the
  active screen?". Use as a guard on `do_update/2` clauses in `App`.
  """
  defguard is_routable(msg)
           when is_tuple(msg) and tuple_size(msg) == 3 and
                  elem(msg, 0) in @routable_topics

  @type topic :: :board_activity | :thread_activity | :board_screen | :board_chat

  @doc "Returns the canonical list of routable broadcast topics."
  @spec topics() :: nonempty_list(topic())
  def topics, do: @routable_topics

  @doc """
  Forwards a broadcast to the active screen via `Routing.route_screen_update/3`.

  Caller is `Foglet.TUI.App.do_update/2`, which only invokes us under the
  `is_routable/1` guard; we don't reassert the App struct here to avoid a
  compile-time cycle (`App` requires this module for the defguard, so this
  module cannot reference `App.t/0` in its specs).
  """
  @spec forward(struct(), tuple()) :: {struct(), [Raxol.Core.Runtime.Command.t()]}
  def forward(state, msg) when is_routable(msg) do
    Routing.route_screen_update(state, Routing.screen_key(Routing.current_route(state)), msg)
  end
end
