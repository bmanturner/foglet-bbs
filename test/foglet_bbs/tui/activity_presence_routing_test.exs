defmodule Foglet.TUI.ActivityPresenceRoutingTest do
  use ExUnit.Case, async: false

  alias Foglet.Sessions.ActivityPresence
  alias Foglet.TUI.App
  alias Foglet.TUI.App.Effects
  alias Foglet.TUI.Effect

  setup do
    user = %Foglet.Accounts.User{id: "user-" <> Ecto.UUID.generate(), handle: "alice"}
    state = %App{current_user: user, session_context: %{domain: %{}}, terminal_size: {80, 24}}
    board = %{id: "b1", name: "General", chat_enabled: false}
    thread = %{id: "t1", board_id: "b1", title: "Welcome"}

    on_exit(fn -> ActivityPresence.clear(user.id) end)

    %{state: state, user: user, board: board, thread: thread}
  end

  test "app navigation tracks board list, board browsing, reading, composer reading, and clear",
       %{
         state: state,
         user: user,
         board: board,
         thread: thread
       } do
    {state, _cmds} = Effects.apply_effect(state, Effect.navigate(:board_list, %{}))
    assert ActivityPresence.get(user.id) == {:ok, :board_list}

    {state, _cmds} =
      Effects.apply_effect(
        state,
        Effect.navigate(:thread_list, %{board: board, board_id: board.id})
      )

    assert ActivityPresence.get(user.id) == {:ok, {:browsing_board, board}}

    {state, _cmds} =
      Effects.apply_effect(
        state,
        Effect.navigate(:post_reader, %{
          board: board,
          board_id: board.id,
          thread: thread,
          thread_id: thread.id
        })
      )

    assert ActivityPresence.get(user.id) == {:ok, {:reading_board, board}}

    {state, _cmds} =
      Effects.apply_effect(
        state,
        Effect.navigate(:post_composer, %{
          origin: :post_reader,
          board: board,
          board_id: board.id,
          thread: thread,
          thread_id: thread.id
        })
      )

    assert ActivityPresence.get(user.id) == {:ok, {:reading_board, board}}

    {_state, _cmds} = Effects.apply_effect(state, Effect.navigate(:main_menu, %{}))
    assert ActivityPresence.get(user.id) == :error
  end

  test "guest navigation does not create member activity", %{state: state, board: board} do
    guest_state = %{state | current_user: nil}

    {_state, _cmds} =
      Effects.apply_effect(guest_state, Effect.navigate(:thread_list, %{board: board}))

    assert ActivityPresence.list()
           |> Enum.reject(&(&1.user_id != nil)) == []
  end
end
