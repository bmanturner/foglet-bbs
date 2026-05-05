defmodule Foglet.BoardChat.Ephemeral.Room do
  @moduledoc """
  In-memory chat room for a single board with `chat_storage_mode = :ephemeral`.

  State holds an ordered ring buffer of `%{id, board_id, user_id, body,
  inserted_at}` capped at `:soft_cap` (newest-first internally; `recent/1`
  returns oldest-first). A periodic tick purges messages older than
  `:ttl_seconds` and shuts the Room down after `:idle_grace_ms` of no
  traffic so memory is freed for unused boards.

  Server-restart wipes ephemeral state by design — there is no persistence.

  ## Broadcasts

  `post/3` broadcasts `{:board_chat, :new_message, message}` on
  `Foglet.PubSub.board_chat_topic(board_id)` after the message is buffered.
  The event tag matches `Foglet.BoardChat.Permanent` so consumers can
  subscribe to the same topic regardless of storage mode.

  ## Test seams

    * `:now_fn` — `(-> integer())` unix-second clock used for inserted_at
      and TTL comparisons (default `&System.system_time/0`-derived).
    * `:monotonic_fn` — `(-> integer())` millisecond monotonic clock used
      for idle-shutdown bookkeeping.
    * `:tick_interval_ms` — override the default 30_000 ms tick.
    * `:soft_cap`, `:recent_limit`, `:idle_grace_ms`, `:ttl_seconds` —
      override defaults inherited from the Board record.
  """
  use GenServer

  require Logger

  alias Foglet.BoardChat.Body
  alias Foglet.BoardChat.Ephemeral.Registry, as: RoomRegistry

  @default_soft_cap 500
  @default_recent_limit 100
  @default_idle_grace_ms 10 * 60 * 1000
  @default_tick_interval_ms 30_000

  @type message :: %{
          id: binary(),
          board_id: binary(),
          user_id: binary(),
          body: String.t(),
          inserted_at: integer()
        }

  # ---------- Public API ----------

  @doc false
  def start_link(opts) do
    board_id = Keyword.fetch!(opts, :board_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(board_id))
  end

  @doc "Append a message and broadcast it. Returns the stored message map."
  @spec post(binary(), binary(), String.t()) :: {:ok, message()} | {:error, term()}
  def post(board_id, user_id, body)
      when is_binary(board_id) and is_binary(user_id) and is_binary(body) do
    GenServer.call(via_tuple(board_id), {:post, user_id, body})
  end

  @doc "Return non-expired messages in chronological order, oldest first."
  @spec recent(binary()) :: [message()]
  def recent(board_id) when is_binary(board_id) do
    GenServer.call(via_tuple(board_id), :recent)
  end

  @doc "Return current buffer size after purging expired messages (test helper)."
  @spec buffer_size(binary()) :: non_neg_integer()
  def buffer_size(board_id) when is_binary(board_id) do
    GenServer.call(via_tuple(board_id), :buffer_size)
  end

  @doc "Force a purge tick synchronously (test helper)."
  @spec purge_now(binary()) :: :ok
  def purge_now(board_id) when is_binary(board_id) do
    GenServer.call(via_tuple(board_id), :purge_now)
  end

  @doc "Look up the registered pid for a board's room, if any."
  @spec whereis(binary()) :: pid() | nil
  def whereis(board_id) when is_binary(board_id) do
    case Registry.lookup(RoomRegistry, board_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  defp via_tuple(board_id), do: {:via, Registry, {RoomRegistry, board_id}}

  # ---------- GenServer callbacks ----------

  @impl true
  def init(opts) do
    board_id = Keyword.fetch!(opts, :board_id)
    ttl_seconds = Keyword.fetch!(opts, :ttl_seconds)

    soft_cap = Keyword.get(opts, :soft_cap, @default_soft_cap)
    recent_limit = Keyword.get(opts, :recent_limit, @default_recent_limit)
    idle_grace_ms = Keyword.get(opts, :idle_grace_ms, @default_idle_grace_ms)
    tick_interval_ms = Keyword.get(opts, :tick_interval_ms, @default_tick_interval_ms)

    now_fn = Keyword.get(opts, :now_fn, fn -> System.system_time(:second) end)

    monotonic_fn =
      Keyword.get(opts, :monotonic_fn, fn -> System.monotonic_time(:millisecond) end)

    state = %{
      board_id: board_id,
      ttl_seconds: ttl_seconds,
      soft_cap: soft_cap,
      recent_limit: recent_limit,
      idle_grace_ms: idle_grace_ms,
      tick_interval_ms: tick_interval_ms,
      now_fn: now_fn,
      monotonic_fn: monotonic_fn,
      buffer: [],
      last_traffic_at: monotonic_fn.()
    }

    schedule_tick(state)
    {:ok, state}
  end

  @impl true
  def handle_call({:post, user_id, body}, _from, state) do
    case Body.validate(body) do
      {:ok, body} -> store_and_broadcast(user_id, body, state)
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:recent, _from, state) do
    state = purge_expired(state)
    msgs = state.buffer |> Enum.take(state.recent_limit) |> Enum.reverse()
    {:reply, msgs, state}
  end

  def handle_call(:buffer_size, _from, state) do
    state = purge_expired(state)
    {:reply, length(state.buffer), state}
  end

  def handle_call(:purge_now, _from, state) do
    state = purge_expired(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    state = purge_expired(state)

    if idle?(state) do
      {:stop, :normal, state}
    else
      schedule_tick(state)
      {:noreply, state}
    end
  end

  def handle_info(_, state), do: {:noreply, state}

  # ---------- Internals ----------

  defp store_and_broadcast(user_id, body, state) do
    msg = %{
      id: Ecto.UUID.generate(),
      board_id: state.board_id,
      user_id: user_id,
      body: body,
      inserted_at: state.now_fn.()
    }

    buffer =
      [msg | state.buffer]
      |> Enum.take(state.soft_cap)

    state = %{state | buffer: buffer, last_traffic_at: state.monotonic_fn.()}

    broadcast(state.board_id, {:board_chat, :new_message, msg})

    {:reply, {:ok, msg}, state}
  end

  defp schedule_tick(%{tick_interval_ms: interval}) do
    Process.send_after(self(), :tick, interval)
  end

  defp purge_expired(state) do
    cutoff = state.now_fn.() - state.ttl_seconds
    buffer = Enum.take_while(state.buffer, fn %{inserted_at: ts} -> ts > cutoff end)
    %{state | buffer: buffer}
  end

  defp idle?(state) do
    state.monotonic_fn.() - state.last_traffic_at >= state.idle_grace_ms
  end

  defp broadcast(board_id, message) do
    topic = Foglet.PubSub.board_chat_topic(board_id)

    case pubsub_module().broadcast(FogletBbs.PubSub, topic, message) do
      :ok ->
        :ok

      {:error, reason} ->
        # Privacy-safe: ephemeral chat broadcast failures are actionable for
        # operators, but the in-memory message body and user-facing content must
        # never be emitted to logs. Keep context to the topic, fixed event kind,
        # and sanitized result reason, mirroring the permanent chat boundary.
        Logger.warning(
          "BoardChat.Ephemeral.Room broadcast failed: topic=#{inspect(topic)} " <>
            "message_type=:board_chat_new_message reason=#{inspect(reason)}"
        )

        :ok
    end
  end

  defp pubsub_module do
    Application.get_env(:foglet_bbs, :pubsub_module, Phoenix.PubSub)
  end
end
