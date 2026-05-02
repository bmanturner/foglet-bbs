defmodule Foglet.BoardChat do
  @moduledoc """
  Public façade for board chat. Dispatches reads/writes to the configured
  storage backend based on the board's `chat_storage_mode`:

    * `:ephemeral` → `Foglet.BoardChat.Ephemeral` (in-memory, TTL-bounded)
    * `:permanent` → `Foglet.BoardChat.Permanent` (DB-backed)

  Both backends broadcast `{:board_chat, :new_message, message}` on
  `Foglet.PubSub.board_chat_topic(board_id)`. Consumers (TUI ChatRoom view,
  presence widgets) subscribe to that single topic and do not need to know
  which storage mode the board uses.

  ## Message shape

  Permanent backend returns `%Foglet.BoardChat.Message{}` structs (DB rows
  with `body`, `user_id`, `board_id`, `id`, `inserted_at`). Ephemeral
  backend returns plain maps with the same field names but no schema
  metadata. Consumers should pattern-match on the field names rather than
  the struct module.
  """

  alias Foglet.Accounts.User
  alias Foglet.BoardChat.{Ephemeral, Permanent}
  alias Foglet.Boards.Board

  @doc """
  Append a chat message for `board` from `user`. Returns `{:ok, message}`
  on success.

  Returns `{:error, :chat_disabled}` if the board has `chat_enabled = false`,
  and propagates backend-specific validation errors (e.g. body length) from
  the permanent path as `{:error, %Ecto.Changeset{}}`.
  """
  @spec post(Board.t(), User.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def post(%Board{chat_storage_mode: :ephemeral} = board, %User{id: user_id}, body) do
    Ephemeral.post(board, user_id, body)
  end

  def post(%Board{chat_storage_mode: :permanent} = board, %User{} = user, body) do
    Permanent.insert(board, user, body)
  end

  @doc """
  Return up to ~100 recent messages for `board`, oldest-first. Empty list
  if chat is disabled or the backend is unavailable.
  """
  @spec recent(Board.t()) :: [map()]
  def recent(%Board{chat_storage_mode: :ephemeral} = board) do
    Ephemeral.recent(board)
  end

  def recent(%Board{chat_storage_mode: :permanent} = board) do
    Permanent.recent(board.id)
  end
end
