defmodule Foglet.TUI.InitialRouteEnterForwarder do
  @moduledoc """
  One-shot subscription that delivers `:initial_route_enter` to the app's
  `update/2` once, immediately after the Dispatcher starts.

  ## Why this exists

  Raxol's `init/1` callback returns `{:ok, model}` — it cannot return
  commands. That means `Foglet.TUI.App.init/1` cannot fire the
  `:on_route_enter` reducer message that screens use as their canonical
  first-load entry point (the `apply_effect(navigate, ...)` path is the
  only call site that dispatches it during normal navigation).

  For SSH-pubkey-authenticated users whose context arrives in `init/1`
  with `current_user` already populated, this means screens like
  `:main_menu` are mounted without their `:on_route_enter` clause ever
  running — so the oneliners panel (and any other route-entry-driven
  load) renders empty until the user navigates away and back.

  This module is a Raxol `Subscription.custom/2` event source. When Raxol
  starts a custom subscription it calls `start_link(args, context)` where
  `context.pid` is the Dispatcher process. This GenServer:

  1. On `init/1`, sends `{:subscription, :initial_route_enter}` to the
     Dispatcher pid — which routes it through the app's `update/2`.
  2. Immediately stops via `{:stop, :normal, ...}`.

  `Foglet.TUI.App.subscribe/1` only includes this subscription in the
  list while `state.initial_route_enter_pending?` is `true`. The first
  time `update/2` processes `:initial_route_enter` it flips the flag to
  `false`, and the next pass through `subscribe/1` drops the subscription
  — so the forwarder fires exactly once per session.

  ## Lifecycle

  Started and stopped by Raxol's Subscription manager. It is not
  supervised independently; its lifetime is tied to the Dispatcher.
  """

  use GenServer

  @doc """
  Called by `Raxol.Core.Runtime.Subscription.start/2` for `:custom` subscriptions.

  `args` is `%{}` (no parameters).
  `context` is `%{pid: dispatcher_pid}` from the Dispatcher's `setup_subscriptions`.
  """
  def start_link(args, context) do
    GenServer.start_link(__MODULE__, {args, context})
  end

  @impl GenServer
  def init({_args, %{pid: dispatcher_pid}}) do
    send(dispatcher_pid, {:subscription, :initial_route_enter})
    {:ok, %{}, {:continue, :stop}}
  end

  @impl GenServer
  def handle_continue(:stop, state) do
    {:stop, :normal, state}
  end
end
