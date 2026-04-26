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

  @doc """
  Called by `Raxol.Core.Runtime.Subscription.start/2` for `:custom` subscriptions.

  `args` is `%{topics: [String.t()]}`.
  `context` is `%{pid: dispatcher_pid}` from the Dispatcher's `setup_subscriptions`.
  """
  def start_link(args, context) do
    GenServer.start_link(__MODULE__, {args, context})
  end

  @impl GenServer
  def init({%{topics: topics}, %{pid: dispatcher_pid}}) do
    pubsub = FogletBbs.PubSub

    Enum.each(topics, fn topic ->
      Phoenix.PubSub.subscribe(pubsub, topic)
    end)

    {:ok, %{dispatcher_pid: dispatcher_pid, topics: topics, pubsub: pubsub}}
  end

  @impl GenServer
  def handle_info(msg, state) do
    # Forward every arriving message to the Dispatcher as a subscription message
    # so that Raxol routes it through the app's update/2.
    send(state.dispatcher_pid, {:subscription, msg})
    {:noreply, state}
  end
end
