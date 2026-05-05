defmodule Foglet.TUI.MinuteClock do
  @moduledoc """
  Central minute-boundary clock broadcaster for TUI chrome.

  The process broadcasts one PubSub event at the start of each wall-clock
  minute. TUI sessions subscribe through the existing app-level PubSub
  forwarder, so individual screens do not own timers and idle sessions still
  redraw the chrome clock without high-frequency polling.
  """

  use GenServer

  @topic Foglet.PubSub.tui_clock_topic()

  @doc "Starts the clock broadcaster."
  def start_link(opts \\ []) do
    genserver_opts =
      case Keyword.get(opts, :name, __MODULE__) do
        nil -> []
        name -> [name: name]
      end

    GenServer.start_link(__MODULE__, opts, genserver_opts)
  end

  @doc "Returns the canonical PubSub topic for TUI clock ticks."
  @spec topic() :: String.t()
  def topic, do: @topic

  @doc "Broadcasts a minute tick. Exposed for controlled tests and maintenance tasks."
  @spec broadcast_tick(DateTime.t()) :: :ok | {:error, term()}
  def broadcast_tick(%DateTime{} = now) do
    Phoenix.PubSub.broadcast(FogletBbs.PubSub, topic(), {:tui_clock, :minute_tick, now})
  end

  @doc "Milliseconds until the next minute boundary for a UTC DateTime."
  @spec delay_until_next_minute(DateTime.t()) :: pos_integer()
  def delay_until_next_minute(%DateTime{} = now) do
    elapsed_ms = now.second * 1_000 + div(elem(now.microsecond, 0), 1_000)

    case rem(elapsed_ms, 60_000) do
      0 -> 60_000
      elapsed -> 60_000 - elapsed
    end
  end

  @impl GenServer
  def init(opts) do
    now_fun = Keyword.get(opts, :now_fun, &DateTime.utc_now/0)
    timer_fun = Keyword.get(opts, :timer_fun, &Process.send_after/3)

    state = %{now_fun: now_fun, timer_fun: timer_fun, timer_ref: nil}
    {:ok, schedule_next_tick(state)}
  end

  @impl GenServer
  def handle_info(:tick, state) do
    now = state.now_fun.()
    _ = broadcast_tick(now)
    {:noreply, schedule_next_tick(%{state | timer_ref: nil})}
  end

  defp schedule_next_tick(%{now_fun: now_fun, timer_fun: timer_fun} = state) do
    ref = timer_fun.(self(), :tick, delay_until_next_minute(now_fun.()))
    %{state | timer_ref: ref}
  end
end
