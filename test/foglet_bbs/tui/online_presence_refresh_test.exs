defmodule Foglet.TUI.OnlinePresenceRefreshTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Context
  alias Foglet.TUI.Screens.MainMenu
  alias Foglet.TUI.Screens.OnlineNow
  alias Foglet.TUI.Screens.OnlineNow.State, as: OnlineNowState

  test "Main Menu subscribes to global online presence events" do
    assert MainMenu.subscriptions(nil, context()) == [Foglet.PubSub.online_presence_topic()]
  end

  test "Online Now subscribes to global online presence events" do
    assert OnlineNow.subscriptions(nil, context()) == [Foglet.PubSub.online_presence_topic()]
  end

  test "Online Now reloads rows when a presence event arrives" do
    rows = [online_row("alice", "Online")]
    state = %OnlineNowState{status: :loaded, rows: rows, selected_index: 0, last_error: nil}

    {new_state, effects} =
      OnlineNow.update({:online_presence, :activity_changed, %{user_id: "u1"}}, state, context())

    assert new_state.status == :loading

    assert [
             %Foglet.TUI.Effect{
               type: :task,
               payload: %{op: :load_online_now, screen_key: :online_now}
             }
           ] = effects
  end

  test "Main Menu accepts presence events without changing screen-local state" do
    state = MainMenu.init(context())

    assert {^state, []} =
             MainMenu.update(
               {:online_presence, :session_connected, %{user_id: "u1"}},
               state,
               context()
             )
  end

  defp context do
    %Context{
      current_user: %{id: "viewer", handle: "viewer", role: :user},
      terminal_size: {80, 24},
      domain: %{online_now: FakeOnlineNow}
    }
  end

  defp online_row(handle, presence_label) do
    %{
      user: %{id: handle, handle: handle, role: :user},
      handle: handle,
      role: :user,
      presence_label: presence_label
    }
  end

  defmodule FakeOnlineNow do
    def list(_opts), do: []
  end
end
