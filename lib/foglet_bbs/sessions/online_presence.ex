defmodule Foglet.Sessions.OnlinePresence do
  @moduledoc """
  Compact global notification boundary for Online Now refreshes.

  This module does not own presence state. The durable/source-of-truth reads stay
  in `Foglet.Sessions.OnlineNow` and `Foglet.Sessions.PresenceSummary`; this
  boundary only broadcasts low-cardinality events that tell focused TUI screens
  to redraw or reload from those sources.
  """

  alias Foglet.PubSub

  @type event ::
          :session_connected
          | :session_disconnected
          | :session_promoted
          | :session_replaced
          | :activity_changed

  @doc "Broadcast an authenticated online/presence change."
  @spec broadcast(event(), map()) :: :ok
  def broadcast(event, %{user_id: user_id} = payload)
      when is_atom(event) and is_binary(user_id) do
    _ =
      Phoenix.PubSub.broadcast(
        FogletBbs.PubSub,
        PubSub.online_presence_topic(),
        message(event, payload)
      )

    :ok
  end

  def broadcast(_event, _payload), do: :ok

  @doc "Returns the wire message for tests and reducers."
  @spec message(event(), map()) :: {:online_presence, event(), map()}
  def message(event, payload) when is_atom(event) and is_map(payload) do
    {:online_presence, event, payload}
  end
end
