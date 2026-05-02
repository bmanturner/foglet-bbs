defmodule Foglet.BoardChat.PersistenceIsolationTest do
  @moduledoc """
  Verifies that ephemeral chat traffic does not write to
  `board_chat_messages`. Permanent persistence is delivered by C3
  (FOG-251); this guard makes sure C4 cannot regress that boundary.
  """

  use FogletBbs.DataCase, async: false

  alias Foglet.Accounts.User
  alias Foglet.BoardChat
  alias Foglet.BoardChat.Ephemeral.Supervisor, as: EphemeralSupervisor
  alias Foglet.Boards.Board
  alias FogletBbs.Repo

  test "post/3 on an ephemeral board writes zero rows to board_chat_messages" do
    board = %Board{
      id: Ecto.UUID.generate(),
      slug: "ephemeral-only",
      name: "Ephemeral Only",
      chat_enabled: true,
      chat_storage_mode: :ephemeral,
      chat_message_ttl_seconds: 60
    }

    user = %User{id: Ecto.UUID.generate()}

    assert {:ok, _} = BoardChat.post(board, user, "first")
    assert {:ok, _} = BoardChat.post(board, user, "second")

    %{rows: [[count]]} =
      Ecto.Adapters.SQL.query!(Repo, "SELECT COUNT(*) FROM board_chat_messages", [])

    assert count == 0

    EphemeralSupervisor.stop_room(board.id)
  end
end
