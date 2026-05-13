defmodule Mix.Tasks.Foglet.Notifications.CleanupTest do
  use FogletBbs.DataCase, async: false

  import Ecto.Query
  import ExUnit.CaptureIO

  alias Foglet.Notifications
  alias Foglet.Notifications.Notification
  alias FogletBbs.AccountsFixtures

  setup do
    Mix.shell(Mix.Shell.IO)
    :ok
  end

  test "deletes old read notifications through an explicit --days retention window" do
    recipient = AccountsFixtures.user_fixture()
    old_read = notification_fixture!(recipient, %{read_at: ~U[2026-04-01 00:00:00.000000Z]})
    unread = notification_fixture!(recipient)
    set_inserted_at!(unread, ~U[2026-04-01 00:00:00.000000Z])

    output =
      capture_io(fn ->
        Mix.Tasks.Foglet.Notifications.Cleanup.run(["--days", "1"])
      end)

    assert output =~ "Deleted 1 read notifications older than 1 day"
    refute Repo.get(Notification, old_read.id)
    assert Repo.get(Notification, unread.id)
  end

  test "rejects missing or invalid retention windows" do
    output =
      capture_io(:stderr, fn ->
        assert catch_exit(Mix.Tasks.Foglet.Notifications.Cleanup.run([])) == {:shutdown, 1}
      end)

    assert output =~ "Provide --days"

    output =
      capture_io(:stderr, fn ->
        assert catch_exit(Mix.Tasks.Foglet.Notifications.Cleanup.run(["--days", "0"])) ==
                 {:shutdown, 1}
      end)

    assert output =~ "Invalid --days"
  end

  defp notification_fixture!(recipient, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          user_id: recipient.id,
          kind: :mention,
          payload: %{
            board_id: Ecto.UUID.generate(),
            thread_id: Ecto.UUID.generate(),
            post_id: Ecto.UUID.generate(),
            snippet: "fixture"
          }
        },
        attrs
      )

    {:ok, notification} = Notifications.create_notification(attrs)
    notification
  end

  defp set_inserted_at!(notification, inserted_at) do
    {1, _} =
      Repo.update_all(
        from(n in Notification, where: n.id == ^notification.id),
        set: [inserted_at: inserted_at]
      )

    :ok
  end
end
