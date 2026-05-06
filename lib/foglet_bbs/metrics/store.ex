defmodule Foglet.Metrics.Store do
  @moduledoc """
  Privacy-safe in-memory metrics store and Prometheus text renderer.

  The store is VM-local runtime state. It intentionally keeps only counters,
  summary counts/sums, and live gauges with bounded labels. It never stores user
  handles, emails, ids, peers, tokens, fingerprints, raw errors, or session ids.
  """

  use GenServer

  @type labels :: %{optional(atom()) => atom() | String.t() | integer()}

  @counter_specs %{
    "foglet_ssh_sessions_started_total" => "SSH/TUI sessions started by session kind.",
    "foglet_ssh_sessions_disconnected_total" => "SSH/TUI sessions disconnected by session kind.",
    "foglet_ssh_auth_outcomes_total" =>
      "Authentication and promotion outcomes by low-cardinality method/outcome labels.",
    "foglet_ssh_session_replacements_total" => "One-session-per-user replacements performed.",
    "foglet_door_launches_total" => "Door launch attempts by runtime type and outcome.",
    "foglet_door_exits_total" => "Door exits by runtime type and outcome.",
    "foglet_phoenix_requests_total" => "Phoenix request completions by route when available."
  }

  @gauge_specs %{
    "foglet_ssh_sessions_active" => "Live SSH/TUI sessions by kind.",
    "foglet_vm_memory_bytes" => "Erlang VM total memory in bytes.",
    "foglet_vm_run_queue" => "Erlang VM total run queue length."
  }

  @summary_specs %{
    "foglet_door_runtime_seconds" => "Door runtime duration in seconds by runtime type.",
    "foglet_bbs_repo_query_duration_seconds" => "Ecto repo query timings in seconds by phase.",
    "foglet_phoenix_request_duration_seconds" =>
      "Phoenix request duration in seconds by route when available."
  }

  @telemetry_handlers [
    {[:foglet, :session, :connect], :session_connect},
    {[:foglet, :session, :disconnect], :session_disconnect},
    {[:foglet, :session, :promote], :session_promote},
    {[:foglet, :session, :replacement], :session_replacement},
    {[:foglet, :auth, :outcome], :auth_outcome},
    {[:foglet, :door, :launch], :door_launch},
    {[:foglet, :door, :exit], :door_exit},
    {[:foglet, :door, :duration], :door_duration},
    {[:foglet_bbs, :repo, :query], :repo_query},
    {[:phoenix, :endpoint, :stop], :phoenix_stop},
    {[:phoenix, :router_dispatch, :stop], :phoenix_stop}
  ]

  defstruct counters: %{}, summaries: %{}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc false
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @doc "Renders all known metrics in Prometheus text exposition format."
  @spec render() :: String.t()
  def render do
    GenServer.call(__MODULE__, :render)
  end

  @doc false
  @spec increment(String.t(), labels(), number()) :: :ok
  def increment(name, labels \\ %{}, value \\ 1) do
    GenServer.cast(__MODULE__, {:increment, name, normalize_labels(labels), value})
  end

  @doc false
  @spec observe(String.t(), number(), labels()) :: :ok
  def observe(name, value, labels \\ %{}) when is_number(value) do
    GenServer.cast(__MODULE__, {:observe, name, normalize_labels(labels), value})
  end

  @impl true
  def init(_opts) do
    attach_telemetry_handlers()
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call(:reset, _from, _state), do: {:reply, :ok, %__MODULE__{}}

  def handle_call(:render, _from, state), do: {:reply, render_state(state), state}

  @impl true
  def handle_cast({:increment, name, labels, value}, state) do
    key = {name, labels}
    counters = Map.update(state.counters, key, value, &(&1 + value))
    {:noreply, %{state | counters: counters}}
  end

  def handle_cast({:observe, name, labels, value}, state) do
    key = {name, labels}

    summaries =
      Map.update(state.summaries, key, %{count: 1, sum: value}, fn summary ->
        %{count: summary.count + 1, sum: summary.sum + value}
      end)

    {:noreply, %{state | summaries: summaries}}
  end

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  defp attach_telemetry_handlers do
    for {event, tag} <- @telemetry_handlers do
      handler_id = {__MODULE__, event}
      _ = :telemetry.detach(handler_id)

      :ok =
        :telemetry.attach(
          handler_id,
          event,
          &__MODULE__.handle_telemetry/4,
          tag
        )
    end

    :ok
  end

  @doc false
  def handle_telemetry(_event, _measurements, metadata, :session_connect) do
    increment("foglet_ssh_sessions_started_total", %{kind: session_kind(metadata)})
  end

  def handle_telemetry(_event, _measurements, metadata, :session_disconnect) do
    increment("foglet_ssh_sessions_disconnected_total", %{kind: session_kind(metadata)})
  end

  def handle_telemetry(_event, _measurements, metadata, :session_promote) do
    increment("foglet_ssh_auth_outcomes_total", %{
      method: "session_promotion",
      outcome: Map.get(metadata, :outcome, :success)
    })
  end

  def handle_telemetry(_event, _measurements, metadata, :session_replacement) do
    increment("foglet_ssh_session_replacements_total", %{
      path: Map.get(metadata, :path, :authenticated_start)
    })
  end

  def handle_telemetry(_event, _measurements, metadata, :auth_outcome) do
    increment("foglet_ssh_auth_outcomes_total", %{
      method: Map.get(metadata, :method, :unknown),
      outcome: Map.get(metadata, :outcome, :unknown)
    })
  end

  def handle_telemetry(_event, _measurements, metadata, :door_launch) do
    increment("foglet_door_launches_total", %{
      runtime: runtime_type(metadata),
      outcome: Map.get(metadata, :outcome, :success)
    })
  end

  def handle_telemetry(_event, _measurements, metadata, :door_exit) do
    increment("foglet_door_exits_total", %{
      runtime: runtime_type(metadata),
      outcome: Map.get(metadata, :outcome, :exited)
    })
  end

  def handle_telemetry(_event, measurements, metadata, :door_duration) do
    observe("foglet_door_runtime_seconds", seconds(Map.get(measurements, :duration, 0)), %{
      runtime: runtime_type(metadata)
    })
  end

  def handle_telemetry(_event, measurements, _metadata, :repo_query) do
    for phase <- [:total_time, :query_time, :queue_time, :decode_time],
        value = Map.get(measurements, phase),
        is_number(value) do
      observe("foglet_bbs_repo_query_duration_seconds", seconds(value), %{phase: phase})
    end
  end

  def handle_telemetry(_event, measurements, metadata, :phoenix_stop) do
    route = metadata |> Map.get(:route, "unknown") |> safe_label_value()
    duration = Map.get(measurements, :duration, 0)

    increment("foglet_phoenix_requests_total", %{route: route})
    observe("foglet_phoenix_request_duration_seconds", seconds(duration), %{route: route})
  end

  defp render_state(state) do
    [
      render_families(@counter_specs, "counter", state.counters),
      render_families(@summary_specs, "summary", state.summaries),
      render_gauges()
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp render_families(specs, type, samples) do
    samples_by_name = Enum.group_by(samples, fn {{name, _labels}, _value} -> name end)

    specs
    |> Map.keys()
    |> Enum.sort()
    |> Enum.map(fn name ->
      render_family(name, Map.fetch!(specs, name), type, Map.get(samples_by_name, name, []))
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp render_family(_name, _help, _type, []), do: ""

  defp render_family(name, help, "counter", samples) do
    header(name, help, "counter") <> render_counter_samples(samples)
  end

  defp render_family(name, help, "summary", samples) do
    header(name, help, "summary") <> render_summary_samples(samples)
  end

  defp render_counter_samples(samples) do
    samples
    |> Enum.sort_by(fn {{_name, labels}, _value} -> labels end)
    |> Enum.map_join("", fn {{name, labels}, value} -> sample(name, labels, value) end)
  end

  defp render_summary_samples(samples) do
    samples
    |> Enum.sort_by(fn {{_name, labels}, _summary} -> labels end)
    |> Enum.map_join("", fn {{name, labels}, summary} ->
      sample(name <> "_count", labels, summary.count) <>
        sample(name <> "_sum", labels, summary.sum)
    end)
  end

  defp render_gauges do
    active_sessions = active_session_samples()

    samples =
      active_sessions ++
        [
          {"foglet_vm_memory_bytes", %{}, :erlang.memory(:total)},
          {"foglet_vm_run_queue", %{}, :erlang.statistics(:run_queue)}
        ]

    samples_by_name = Enum.group_by(samples, fn {name, _labels, _value} -> name end)

    @gauge_specs
    |> Map.keys()
    |> Enum.sort()
    |> Enum.map_join("\n", fn name ->
      sample_entries = Map.get(samples_by_name, name, [])

      header(name, Map.fetch!(@gauge_specs, name), "gauge") <>
        render_gauge_samples(sample_entries)
    end)
  end

  defp render_gauge_samples(samples) do
    samples
    |> Enum.sort_by(fn {_name, labels, _value} -> labels end)
    |> Enum.map_join("", fn {name, labels, value} -> sample(name, labels, value) end)
  end

  defp active_session_samples do
    counts = active_session_counts()

    for kind <- [:guest, :authenticated, :total] do
      {"foglet_ssh_sessions_active", %{kind: kind}, Map.fetch!(counts, kind)}
    end
  end

  defp active_session_counts do
    if Process.whereis(Foglet.Sessions.Supervisor) do
      Foglet.Sessions.Supervisor
      |> DynamicSupervisor.which_children()
      |> Enum.reduce(%{guest: 0, authenticated: 0, total: 0}, fn {_id, pid, _type, _modules},
                                                                 acc ->
        case safe_session_state(pid) do
          %{user_id: user_id} when is_binary(user_id) ->
            %{acc | authenticated: acc.authenticated + 1, total: acc.total + 1}

          %{user_id: nil} ->
            %{acc | guest: acc.guest + 1, total: acc.total + 1}

          _ ->
            acc
        end
      end)
    else
      %{guest: 0, authenticated: 0, total: 0}
    end
  end

  defp safe_session_state(pid) when is_pid(pid) do
    Foglet.Sessions.Session.get_state(pid)
  catch
    :exit, _ -> nil
  end

  defp header(name, help, type) do
    "# HELP #{name} #{help}\n# TYPE #{name} #{type}\n"
  end

  defp sample(name, labels, value) do
    "#{name}#{format_labels(labels)} #{format_number(value)}\n"
  end

  defp format_labels(labels) when map_size(labels) == 0, do: ""

  defp format_labels(labels) do
    rendered =
      labels
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.map_join(",", fn {key, value} ->
        ~s(#{key}="#{safe_label_value(value)}")
      end)

    "{" <> rendered <> "}"
  end

  defp format_number(value) when is_integer(value), do: Integer.to_string(value)
  defp format_number(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 9)

  defp normalize_labels(labels) do
    labels
    |> Enum.map(fn {key, value} -> {key, safe_label_value(value)} end)
    |> Map.new()
  end

  defp session_kind(%{kind: :authenticated}), do: :authenticated
  defp session_kind(%{kind: "authenticated"}), do: :authenticated
  defp session_kind(%{user_id: user_id}) when is_binary(user_id), do: :authenticated
  defp session_kind(_metadata), do: :guest

  defp runtime_type(%{runtime: runtime})
       when runtime in [:native_elixir, :external_pty, :classic_dropfile],
       do: runtime

  defp runtime_type(%{runtime: runtime})
       when runtime in ["native_elixir", "external_pty", "classic_dropfile"],
       do: runtime

  defp runtime_type(_metadata), do: :unknown

  defp seconds(native) when is_integer(native),
    do: System.convert_time_unit(native, :native, :microsecond) / 1_000_000

  defp seconds(value) when is_float(value), do: value

  defp safe_label_value(value) when is_atom(value), do: Atom.to_string(value)
  defp safe_label_value(value) when is_integer(value), do: Integer.to_string(value)

  defp safe_label_value(value) when is_binary(value) do
    value
    |> String.replace(~r/[^A-Za-z0-9_:\/.\-]/, "_")
    |> String.slice(0, 80)
  end

  defp safe_label_value(_value), do: "unknown"
end
