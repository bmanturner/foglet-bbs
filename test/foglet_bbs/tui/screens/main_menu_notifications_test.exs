defmodule Foglet.TUI.Screens.MainMenuNotificationsTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.RenderHelpers

  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Screens.MainMenu
  alias Foglet.TUI.Screens.MainMenu.State

  defmodule FakeOnlineNow do
    def count, do: 7
  end

  defmodule FakeNotifications do
    def unread_count(_user) do
      Process.put(:fake_notifications_unread_count_called, true)
      3
    end
  end

  defp context(opts \\ []) do
    user = Keyword.get(opts, :current_user, %{id: "viewer", handle: "viewer", role: :user})

    Context.new(
      current_user: user,
      route: :main_menu,
      terminal_size: Keyword.get(opts, :terminal_size, {80, 24}),
      unread_count: Keyword.get(opts, :unread_count, 0),
      domain: %{online_now: FakeOnlineNow, notifications: FakeNotifications}
    )
  end

  defp local_state(attrs \\ %{}) do
    struct!(State, Map.merge(%{recent_oneliners: [], selected_oneliner_index: 0}, Map.new(attrs)))
  end

  defp task_effect!(effects, op) do
    Enum.find(effects, fn
      %Effect{type: :task, payload: %{op: ^op, screen_key: screen_key}} ->
        screen_key == Effect.current_screen_key()

      _ ->
        false
    end) || flunk("expected task effect #{inspect(op)}, got #{inspect(effects)}")
  end

  test "route entry loads both oneliners and unread notification count" do
    {loading, effects} = MainMenu.update(:on_route_enter, local_state(), context())

    assert loading.oneliner_status == :loading
    assert loading.notifications_status == :loading

    oneliner_task = task_effect!(effects, :load_oneliners)
    unread_task = task_effect!(effects, :load_unread_notifications_count)

    assert 3 = unread_task.payload.fun.()
    assert Process.get(:fake_notifications_unread_count_called) == true
    assert is_function(oneliner_task.payload.fun, 0)
  end

  test "screen subscribes to notification topics and polls unread count while active" do
    subscriptions = MainMenu.subscriptions(local_state(), context())

    assert subscriptions.topics == [
             Foglet.PubSub.online_presence_topic(),
             Foglet.PubSub.notifications_topic("viewer")
           ]

    assert subscriptions.intervals == [{2_000, :refresh_unread_notifications_count}]
  end

  test "unread count task result updates local state for render" do
    {updated, []} =
      MainMenu.update(
        {:task_result, :load_unread_notifications_count, {:ok, 5}},
        local_state(),
        context()
      )

    assert updated.unread_notifications_count == 5
    assert updated.notifications_status == :idle
  end

  test "notification PubSub events apply the app-shell unread count and request authoritative reload" do
    {updated, effects} =
      MainMenu.update(
        {:notifications, :created, %{user_id: "viewer"}},
        local_state(),
        context(unread_count: 4)
      )

    assert updated.notifications_status == :idle
    assert updated.unread_notifications_count == 4
    assert [%Effect{type: :task, payload: %{op: :load_unread_notifications_count}}] = effects
  end

  test "inbox key routes to the notifications screen" do
    {_local, effects} =
      MainMenu.update({:key, %{key: :char, char: "I"}}, local_state(), context())

    assert Enum.any?(
             effects,
             &match?(%Effect{type: :navigate, payload: %{screen: :notifications}}, &1)
           )
  end

  test "render shows the inbox destination with a distinct unread badge" do
    view = MainMenu.render(local_state(%{unread_notifications_count: 12}), context())
    texts = collect_text_values(view)

    assert Enum.any?(texts, &String.contains?(&1, "✉ Inbox"))
    assert "[12]" in texts
    assert "[I]" in texts
  end

  test "render hides the inbox badge at zero unread" do
    view = MainMenu.render(local_state(%{unread_notifications_count: 0}), context())
    texts = collect_text_values(view)

    assert Enum.any?(texts, &String.contains?(&1, "✉ Inbox"))
    refute "[0]" in texts
    refute Enum.any?(texts, &String.contains?(&1, "Inbox (0)"))
  end
end
