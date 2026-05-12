defmodule Foglet.TUI.OnlinePresenceRefreshTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Context
  alias Foglet.TUI.Screens.MainMenu
  alias Foglet.TUI.Screens.OnlineNow
  alias Foglet.TUI.Screens.OnlineNow.State, as: OnlineNowState

  test "Main Menu subscribes to global online presence events" do
    assert Foglet.PubSub.online_presence_topic() in MainMenu.subscriptions(nil, context())
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

  test "Main Menu presence events bump screen state so focused Raxol model refreshes" do
    state = MainMenu.init(context())

    assert {new_state, []} =
             MainMenu.update(
               {:online_presence, :session_connected, %{user_id: "u1"}},
               state,
               context()
             )

    assert new_state != state
    assert Map.get(new_state, :presence_refresh_revision) == 1
  end

  defp context do
    Context.new(
      current_user: %Foglet.Accounts.User{id: "viewer", handle: "viewer", role: :user},
      terminal_size: {80, 24},
      route: :main_menu,
      domain: %{online_now: FakeOnlineNow}
    )
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
    def count, do: Process.get(:fake_online_now_count, 0)
    def list(_opts), do: []
  end
end
