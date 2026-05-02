defmodule Foglet.BoardChat.Ephemeral do
  @moduledoc """
  Ephemeral chat backend.

  Thin facade over `Foglet.BoardChat.Ephemeral.Supervisor` and
  `Foglet.BoardChat.Ephemeral.Room`. Callers go through
  `Foglet.BoardChat`, which dispatches here when a board's
  `chat_storage_mode` is `:ephemeral`.

  Each call ensures a Room is running for the board (lazy-started under the
  ephemeral DynamicSupervisor). Room defaults are taken from the Board
  record, but tests can override them via the optional `room_opts` argument.
  """

  alias Foglet.BoardChat.Ephemeral.{Room, Supervisor}
  alias Foglet.Boards.Board

  @doc "Append a chat message for `board` and broadcast it on the chat topic."
  @spec post(Board.t(), binary(), String.t(), keyword()) ::
          {:ok, Room.message()} | {:error, term()}
  def post(%Board{} = board, user_id, body, room_opts \\ [])
      when is_binary(user_id) and is_binary(body) do
    with :ok <- ensure_chat_enabled(board),
         :ok <- ensure_ephemeral(board),
         {:ok, _pid} <- ensure_room(board, room_opts) do
      Room.post(board.id, user_id, body)
    end
  end

  @doc "Return the non-expired tail of `board`'s ephemeral buffer (oldest-first)."
  @spec recent(Board.t(), keyword()) :: [Room.message()]
  def recent(%Board{} = board, room_opts \\ []) do
    with :ok <- ensure_chat_enabled(board),
         :ok <- ensure_ephemeral(board),
         {:ok, _pid} <- ensure_room(board, room_opts) do
      Room.recent(board.id)
    else
      _ -> []
    end
  end

  @doc "Stop the Room for `board` if running. Admin/test helper."
  @spec stop(Board.t()) :: :ok
  def stop(%Board{id: board_id}), do: Supervisor.stop_room(board_id)

  defp ensure_room(%Board{id: board_id} = board, room_opts) do
    opts = Keyword.put_new(room_opts, :ttl_seconds, board.chat_message_ttl_seconds)
    Supervisor.ensure_room(board_id, opts)
  end

  defp ensure_chat_enabled(%Board{chat_enabled: true}), do: :ok
  defp ensure_chat_enabled(%Board{}), do: {:error, :chat_disabled}

  defp ensure_ephemeral(%Board{chat_storage_mode: :ephemeral}), do: :ok
  defp ensure_ephemeral(%Board{}), do: {:error, :not_ephemeral}
end
