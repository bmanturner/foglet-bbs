defmodule Foglet.TUI.PubSubForwarder do
  @moduledoc """
  Bridges Phoenix.PubSub topics into the Raxol Dispatcher's update/2 loop.

  ## Why this exists

  Raxol's Lifecycle and Dispatcher do NOT route arbitrary Erlang messages to
  the app's `update/2`. Only messages wrapped as `{:subscription, msg}` by
  Raxol's internal timer/event infrastructure reach `update/2` (via
  `handle_manager_info({:subscription, msg}, state)` in the Dispatcher).

  This module is a Raxol `Subscription.custom/2` event source. When Raxol
  starts a custom subscription it calls `start_link(args, context)` where
  `context.pid` is the Dispatcher process. This GenServer:

  1. Subscribes to every Phoenix.PubSub topic in `args.topics`.
  2. On each arriving PubSub message, sends `{:subscription, msg}` to the
     Dispatcher pid — which routes it through the app's `update/2`.

  ## Lifecycle

  The forwarder is started and stopped by Raxol's Subscription manager. It is
  *not* supervised independently; its lifetime is tied to the Dispatcher
  process. When the Dispatcher exits, this GenServer exits too (via the linked
  start).

  ## Topic conventions (Audit #12)

  Topic strings are constructed by `Foglet.PubSub`, which is the canonical
  source of truth. The four patterns are:

  - `"user:<user_id>"` — per-user notifications / DMs
  - `"boards"` — aggregate board activity (new posts, read-pointer changes)
  - `"board:<board_id>"` — per-board thread activity
  - `"thread:<thread_id>"` — per-thread new posts

  Phase 2 may not yet broadcast to all topics; subscriptions are wired now so
  the TUI reacts automatically once Phase 2 starts emitting events.
  """

  use GenServer

  @control_topic_prefix "tui:pubsub_forwarder:"
  @unread_poll_ms 2_000

  @doc "Ensures a dispatcher-owned forwarder exists, then refreshes its topics."
  def ensure_refreshed(dispatcher_pid \\ self(), topics)
      when is_pid(dispatcher_pid) and is_list(topics) do
    case :global.whereis_name(registry_name(dispatcher_pid)) do
      pid when is_pid(pid) ->
        refresh(dispatcher_pid, topics)

      :undefined ->
        case start(%{topics: topics}, %{pid: dispatcher_pid}) do
          {:ok, _pid} -> refresh(dispatcher_pid, topics)
          {:error, {:already_started, _pid}} -> refresh(dispatcher_pid, topics)
          {:error, _reason} = error -> error
        end
    end
  end

  @doc "Broadcasts a topic refresh to the forwarder owned by `dispatcher_pid`."
  def refresh(dispatcher_pid \\ self(), topics) when is_pid(dispatcher_pid) and is_list(topics) do
    message = {:pubsub_forwarder, {:refresh_topics, normalize_topics(topics)}}

    case :global.whereis_name(registry_name(dispatcher_pid)) do
      pid when is_pid(pid) -> send(pid, message)
      :undefined -> :ok
    end

    Phoenix.PubSub.broadcast(
      FogletBbs.PubSub,
      control_topic(dispatcher_pid),
      message
    )
  end

  @doc "Returns the private control topic for a dispatcher-owned forwarder."
  def control_topic(dispatcher_pid) when is_pid(dispatcher_pid) do
    @control_topic_prefix <> List.to_string(:erlang.pid_to_list(dispatcher_pid))
  end

  @doc """
  Called by `Raxol.Core.Runtime.Subscription.start/2` for `:custom` subscriptions.

  `args` is `%{topics: [String.t()]}`.
  `context` is `%{pid: dispatcher_pid}` from the Dispatcher's `setup_subscriptions`.
  """
  def start_link(args, context) do
    GenServer.start_link(__MODULE__, {args, context})
  end

  @doc "Starts an unlinked dispatcher-owned forwarder for dynamic login/topic refreshes."
  def start(args, context) do
    GenServer.start(__MODULE__, {args, context})
  end

  @impl GenServer
  def init({%{topics: topics}, %{pid: dispatcher_pid}}) do
    pubsub = FogletBbs.PubSub
    topics = normalize_topics(topics)
    control_topic = control_topic(dispatcher_pid)

    :ok = Phoenix.PubSub.subscribe(pubsub, control_topic)
    dispatcher_ref = Process.monitor(dispatcher_pid)
    _ = :global.register_name(registry_name(dispatcher_pid), self())
    subscribe_topics(pubsub, topics)
    schedule_unread_poll()

    {:ok,
     %{
       dispatcher_pid: dispatcher_pid,
       dispatcher_ref: dispatcher_ref,
       control_topic: control_topic,
       topics: topics,
       pubsub: pubsub,
       last_forwarded: nil,
       last_unread_count: nil
     }}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{dispatcher_ref: ref} = state) do
    {:stop, :normal, state}
  end

  @impl GenServer
  def handle_info({:pubsub_forwarder, {:refresh_topics, topics}}, state) do
    topics = normalize_topics(topics)
    current = MapSet.new(state.topics)
    next = MapSet.new(topics)

    state.pubsub
    |> unsubscribe_topics(MapSet.difference(current, next))

    state.pubsub
    |> subscribe_topics(MapSet.difference(next, current))

    {:noreply, %{state | topics: topics}}
  end

  def handle_info(:poll_unread_count, state) do
    state = poll_unread_count(state)
    schedule_unread_poll()
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(msg, %{last_forwarded: msg} = state) do
    {:noreply, state}
  end

  def handle_info(msg, state) do
    # Forward every arriving message to the Dispatcher as a subscription message
    # so that Raxol routes it through the app's update/2.
    send(state.dispatcher_pid, {:subscription, msg})
    {:noreply, %{state | last_forwarded: msg}}
  end

  @impl GenServer
  def terminate(_reason, state) do
    :global.unregister_name(registry_name(state.dispatcher_pid))
    :ok
  end

  defp normalize_topics(topics) do
    topics
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp registry_name(dispatcher_pid), do: {__MODULE__, dispatcher_pid}

  defp schedule_unread_poll do
    Process.send_after(self(), :poll_unread_count, @unread_poll_ms)
  end

  defp poll_unread_count(state) do
    case notification_user_id(state.topics) do
      nil ->
        %{state | last_unread_count: nil}

      user_id ->
        count = Foglet.Notifications.unread_count(user_id)

        if count != state.last_unread_count do
          send(
            state.dispatcher_pid,
            {:subscription,
             {:screen_task_result, :main_menu, :load_unread_notifications_count, {:ok, count}}}
          )
        end

        %{state | last_unread_count: count}
    end
  end

  defp notification_user_id(topics) do
    Enum.find_value(topics, fn
      "notifications:" <> user_id -> user_id
      _other -> nil
    end)
  end

  defp subscribe_topics(pubsub, topics) do
    Enum.each(topics, &Phoenix.PubSub.subscribe(pubsub, &1))
  end

  defp unsubscribe_topics(pubsub, topics) do
    Enum.each(topics, &Phoenix.PubSub.unsubscribe(pubsub, &1))
  end
end
