defmodule Foglet.TUI.Screens.NotificationsTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.RenderHelpers

  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Screens.Notifications
  alias Foglet.TUI.Screens.Notifications.State

  defmodule FakeNotifications do
    def list_recent(_user, limit \\ 50) do
      Process.put(:fake_notifications_list_recent_limit, limit)
      notifications()
    end

    def mark_read(_user, notification_id) do
      Process.put(:fake_notifications_mark_read, notification_id)
      {:ok, Enum.find(notifications(), &(&1.id == notification_id))}
    end

    def mark_all_read(_user) do
      Process.put(:fake_notifications_mark_all_read, true)
      {:ok, 2}
    end

    defp notifications do
      [
        %{
          id: "n-1",
          kind: :mention,
          read_at: nil,
          inserted_at: ~U[2026-05-11 21:30:00Z],
          actor: %{handle: "alice", role: :sysop},
          payload: %{
            "snippet" => "Check this thread",
            "thread_id" => "t1",
            "board_id" => "b1",
            "post_id" => "p1"
          }
        },
        %{
          id: "n-2",
          kind: :dm,
          read_at: ~U[2026-05-11 21:31:00Z],
          inserted_at: ~U[2026-05-11 21:31:00Z],
          actor: %{handle: "bob", role: :user},
          payload: %{"preview" => "hello there", "message_id" => "m1"}
        }
      ]
    end
  end

  defp context(opts \\ []) do
    Context.new(
      current_user:
        Keyword.get(opts, :current_user, %{id: "viewer", handle: "viewer", role: :user}),
      route: :notifications,
      terminal_size: Keyword.get(opts, :terminal_size, {80, 24}),
      domain: %{notifications: FakeNotifications}
    )
  end

  test "route entry loads inbox rows through the runtime task boundary" do
    local = Notifications.init(context())

    {loading, effects} = Notifications.update(:on_route_enter, local, context())

    assert loading.status == :loading

    assert [
             %Effect{
               type: :task,
               payload: %{op: :load_notifications, screen_key: :notifications, fun: fun}
             }
           ] = effects

    assert length(fun.()) == 2
    assert Process.get(:fake_notifications_list_recent_limit) == 50
  end

  test "screen subscribes to the current user's notifications topic" do
    topics = Notifications.subscriptions(nil, context())

    assert topics == [Foglet.PubSub.notifications_topic("viewer")]
  end

  test "loaded rows render kind, source, summary, and actions" do
    local =
      State.from_rows(
        Notifications.init(context()),
        FakeNotifications.list_recent(%{id: "viewer"})
      )

    texts = Notifications.render(local, context()) |> collect_text_values()

    assert Enum.any?(texts, &String.contains?(&1, "Inbox"))
    assert Enum.any?(texts, &String.contains?(&1, "[mention]"))
    assert Enum.any?(texts, &String.contains?(&1, "from @alice"))
    assert Enum.any?(texts, &String.contains?(&1, "Check this thread"))
    assert Enum.any?(texts, &String.contains?(&1, "Mark read"))
    assert Enum.any?(texts, &String.contains?(&1, "Mark all read"))
  end

  test "80x24 layout keeps the selected summary visible in the detail panel" do
    local =
      State.from_rows(
        Notifications.init(context(terminal_size: {80, 24})),
        FakeNotifications.list_recent(%{id: "viewer"})
      )

    texts =
      Notifications.render(local, context(terminal_size: {80, 24}))
      |> collect_text_values()

    assert Enum.any?(texts, &String.contains?(&1, "Summary"))
    assert Enum.any?(texts, &String.contains?(&1, "Check this thread"))
  end

  test "wide layouts render a selected-item detail panel" do
    local =
      State.from_rows(
        Notifications.init(context(terminal_size: {100, 30})),
        FakeNotifications.list_recent(%{id: "viewer"})
      )

    texts =
      Notifications.render(local, context(terminal_size: {100, 30}))
      |> collect_text_values()

    assert Enum.any?(texts, &String.contains?(&1, "Kind          Mention"))
    assert Enum.any?(texts, &String.contains?(&1, "Source        from @alice"))
    assert Enum.any?(texts, &String.contains?(&1, "Read state"))
    assert Enum.any?(texts, &String.contains?(&1, "from @alice"))
  end

  test "mark read key calls the notifications context through a task effect" do
    local =
      State.from_rows(
        Notifications.init(context()),
        FakeNotifications.list_recent(%{id: "viewer"})
      )

    {marking, effects} = Notifications.update({:key, %{key: :char, char: "r"}}, local, context())

    assert marking.status == :marking_read

    assert [
             %Effect{
               type: :task,
               payload: %{op: :mark_notification_read, screen_key: :notifications, fun: fun}
             }
           ] = effects

    assert {:ok, %{id: "n-1"}} = fun.()
    assert Process.get(:fake_notifications_mark_read) == "n-1"
  end

  test "notification PubSub events trigger a focused inbox reload" do
    local = Notifications.init(context())

    {loading, effects} =
      Notifications.update({:notifications, :created, %{user_id: "viewer"}}, local, context())

    assert loading.status == :loading

    assert [
             %Effect{type: :task, payload: %{op: :load_notifications, screen_key: :notifications}}
           ] = effects
  end

  test "back keys route to the main menu" do
    for key <- ["q", "Q", "b", "B"] do
      {_local, effects} =
        Notifications.update(
          {:key, %{key: :char, char: key}},
          Notifications.init(context()),
          context()
        )

      assert Enum.any?(
               effects,
               &match?(%Effect{type: :navigate, payload: %{screen: :main_menu}}, &1)
             )
    end
  end
end
