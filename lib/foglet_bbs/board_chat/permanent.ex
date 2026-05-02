defmodule Foglet.BoardChat.Permanent do
  @moduledoc """
  Persistence context for permanent board chat (FOG-242 C3).

  Owns durable writes and the bounded recent-history query for boards
  configured with `chat_storage_mode = :permanent`. Inserts broadcast on
  the canonical `Foglet.PubSub.board_chat_topic/1` so live consumers
  (TUI screens, screen-presence widgets) receive new messages without
  polling.

  Boards configured for ephemeral chat are rejected at the boundary —
  the ephemeral path is owned by a separate context (FOG-242 C4) and
  must not coexist with durable rows for the same board.
  """

  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias Foglet.Accounts.User
  alias Foglet.BoardChat.Message
  alias Foglet.Boards.Board
  alias FogletBbs.Repo

  @recent_default_limit 100
  @recent_max_limit 100

  @doc "Board-approved upper bound on the recent-messages query."
  def recent_max_limit, do: @recent_max_limit

  @doc """
  Insert a chat message for `board` from `user`. Broadcasts
  `{:board_chat, :new_message, %Message{}}` on
  `Foglet.PubSub.board_chat_topic(board.id)` after a successful write.

  Returns:
    * `{:ok, %Message{}}`
    * `{:error, %Ecto.Changeset{}}` for validation failures
    * `{:error, :chat_disabled}` if the board has `chat_enabled = false`
    * `{:error, :not_permanent}` if the board's `chat_storage_mode` is
      not `:permanent`
  """
  @spec insert(Board.t(), User.t(), String.t()) ::
          {:ok, Message.t()}
          | {:error, Changeset.t()}
          | {:error, :chat_disabled | :not_permanent}
  def insert(%Board{} = board, %User{} = user, body) do
    with :ok <- ensure_chat_enabled(board),
         :ok <- ensure_permanent(board) do
      %Message{board_id: board.id, user_id: user.id}
      |> Message.insert_changeset(%{body: body})
      |> Repo.insert()
      |> case do
        {:ok, message} ->
          broadcast_new_message(board.id, message)
          {:ok, message}

        {:error, _changeset} = err ->
          err
      end
    end
  end

  @doc """
  Return up to `limit` of the most recently inserted messages on `board_id`,
  ordered oldest → newest so the caller can append directly.

  `limit` is clamped to `recent_max_limit/0` (currently 100). The query is
  served by the `(board_id, inserted_at)` composite index — the planner
  scans backward for the inner `ORDER BY inserted_at DESC LIMIT ?` and the
  outer `Enum.reverse/1` puts rows back in chronological order.
  """
  @spec recent(Ecto.UUID.t(), pos_integer()) :: [Message.t()]
  def recent(board_id, limit \\ @recent_default_limit) when is_binary(board_id) do
    bounded =
      cond do
        not is_integer(limit) -> @recent_default_limit
        limit < 1 -> @recent_default_limit
        limit > @recent_max_limit -> @recent_max_limit
        true -> limit
      end

    Message
    |> where([m], m.board_id == ^board_id)
    |> order_by([m], desc: m.inserted_at)
    |> limit(^bounded)
    |> Repo.all()
    |> Enum.reverse()
  end

  defp ensure_chat_enabled(%Board{chat_enabled: true}), do: :ok
  defp ensure_chat_enabled(%Board{}), do: {:error, :chat_disabled}

  defp ensure_permanent(%Board{chat_storage_mode: :permanent}), do: :ok
  defp ensure_permanent(%Board{}), do: {:error, :not_permanent}

  defp broadcast_new_message(board_id, %Message{} = message) do
    _ =
      Phoenix.PubSub.broadcast(
        FogletBbs.PubSub,
        Foglet.PubSub.board_chat_topic(board_id),
        {:board_chat, :new_message, message}
      )

    :ok
  end
end
