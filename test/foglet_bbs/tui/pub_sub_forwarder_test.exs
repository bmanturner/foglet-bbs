defmodule Foglet.TUI.PubSubForwarderTest do
  use FogletBbs.DataCase, async: false

  import FogletBbs.AccountsFixtures

  alias Foglet.{DMs, Notifications, PubSub}
  alias Foglet.TUI.PubSubForwarder

  test "polling emits mail refresh when DM unread changes without notification unread changing" do
    sender = user_fixture(%{handle: "dmfs#{System.unique_integer([:positive])}"})
    recipient = user_fixture(%{handle: "dmfr#{System.unique_integer([:positive])}"})
    dispatcher_pid = self()

    {:ok, forwarder} =
      PubSubForwarder.start_link(
        %{topics: [PubSub.notifications_topic(recipient.id)]},
        %{pid: dispatcher_pid}
      )

    send(forwarder, :poll_unread_count)

    assert_receive {:subscription,
                    {:screen_task_result, :main_menu, :load_unread_notifications_count, {:ok, 0}}}

    assert_receive {:subscription, :refresh_mail}

    send(forwarder, :poll_unread_count)
    refute_receive {:subscription, :refresh_mail}, 100

    {:ok, _message} = DMs.send_message(sender, recipient, %{body: "poll refresh"})
    {:ok, _} = Notifications.mark_all_read(recipient)

    send(forwarder, :poll_unread_count)

    assert_receive {:subscription, :refresh_mail}
  end
end
