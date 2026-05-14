defmodule Foglet.DMsTest do
  use FogletBbs.DataCase, async: true

  import FogletBbs.AccountsFixtures

  alias Foglet.Accounts
  alias Foglet.DMs
  alias Foglet.DMs.Message
  alias Foglet.Moderation
  alias Foglet.Notifications
  alias FogletBbs.Repo

  describe "send_message/3" do
    test "persists a DM and emits one durable notification for the recipient" do
      sender = user_fixture(%{handle: "sender#{System.unique_integer([:positive])}"})
      recipient = user_fixture(%{handle: "recipient#{System.unique_integer([:positive])}"})

      assert {:ok, %Message{} = message} =
               DMs.send_message(sender, recipient, %{body: "hello **there**"})

      assert message.sender_id == sender.id
      assert message.recipient_id == recipient.id
      assert message.body == "hello **there**"
      assert is_nil(message.read_at)

      assert [notification] = Notifications.list_recent(recipient)
      assert notification.kind == :dm
      assert notification.user_id == recipient.id
      assert notification.actor_id == sender.id
      assert notification.payload["message_id"] == message.id
      assert notification.payload["preview"] == "hello **there**"
      assert Notifications.list_recent(sender) == []

      assert {:ok, target} = Notifications.resolve_open_target(recipient, notification)
      assert target.kind == :dm
      assert target.message_id == message.id
      assert target.participant_id == sender.id
    end

    test "rejects self-DMs and blank bodies" do
      user = user_fixture()
      other = user_fixture()

      assert {:error, :cannot_message_self} = DMs.send_message(user, user, %{body: "hello"})
      assert {:error, changeset} = DMs.send_message(user, other, %{body: "   "})
      assert %{body: [message | _]} = errors_on(changeset)
      assert message =~ "blank"
    end
  end

  describe "conversation and unread state" do
    test "lists two-party conversation chronologically with delete-from-my-view filtering" do
      alice = user_fixture(%{handle: "alice#{System.unique_integer([:positive])}"})
      bob = user_fixture(%{handle: "bob#{System.unique_integer([:positive])}"})

      {:ok, first} = DMs.send_message(alice, bob, %{body: "first"})
      {:ok, second} = DMs.send_message(bob, alice, %{body: "second"})
      {:ok, third} = DMs.send_message(alice, bob, %{body: "third"})

      assert Enum.map(DMs.list_conversation(alice, bob), & &1.id) == [
               first.id,
               second.id,
               third.id
             ]

      assert Enum.map(DMs.list_conversation(bob, alice), & &1.id) == [
               first.id,
               second.id,
               third.id
             ]

      assert {:ok, deleted_first} = DMs.delete_from_my_view(alice, first)
      assert deleted_first.id == first.id
      assert deleted_first.deleted_by_sender_at
      assert Enum.map(DMs.list_conversation(alice, bob), & &1.id) == [second.id, third.id]

      assert Enum.map(DMs.list_conversation(bob, alice), & &1.id) == [
               first.id,
               second.id,
               third.id
             ]
    end

    test "summarizes visible conversations for inbox and sent views" do
      alice = user_fixture(%{handle: "alice#{System.unique_integer([:positive])}"})
      bob = user_fixture(%{handle: "bob#{System.unique_integer([:positive])}"})
      carol = user_fixture(%{handle: "carol#{System.unique_integer([:positive])}"})

      {:ok, _bob_to_alice} = DMs.send_message(bob, alice, %{body: "bob ping"})
      {:ok, _alice_to_bob} = DMs.send_message(alice, bob, %{body: "alice reply"})
      {:ok, _carol_to_alice} = DMs.send_message(carol, alice, %{body: "carol ping"})

      inbox = DMs.list_conversations(alice, :inbox)
      sent = DMs.list_conversations(alice, :sent)

      assert Enum.map(inbox, & &1.participant.id) |> Enum.sort() == Enum.sort([bob.id, carol.id])
      assert Enum.map(sent, & &1.participant.id) == [bob.id]
      assert Enum.find(inbox, &(&1.participant.id == carol.id)).unread_count == 1
    end

    test "marks only visible recipient messages read and tracks unread counts by conversation" do
      alice = user_fixture(%{handle: "alice#{System.unique_integer([:positive])}"})
      bob = user_fixture(%{handle: "bob#{System.unique_integer([:positive])}"})
      carol = user_fixture(%{handle: "carol#{System.unique_integer([:positive])}"})

      {:ok, _sent_by_alice} = DMs.send_message(alice, bob, %{body: "from alice"})
      {:ok, _sent_by_carol} = DMs.send_message(carol, bob, %{body: "from carol"})
      {:ok, _reply_from_bob} = DMs.send_message(bob, alice, %{body: "reply"})

      assert DMs.unread_count(bob) == 2
      assert DMs.conversation_unread_counts(bob) == %{alice.id => 1, carol.id => 1}

      assert {:ok, 1} = DMs.mark_conversation_read(bob, alice)
      assert DMs.unread_count(bob) == 1
      assert DMs.conversation_unread_counts(bob) == %{carol.id => 1}
    end
  end

  describe "moderation reports" do
    test "DMs are valid report targets" do
      reporter = user_fixture()
      recipient = user_fixture()
      {:ok, message} = DMs.send_message(reporter, recipient, %{body: "reportable"})

      assert {:ok, report} =
               Moderation.create_report(reporter, %{
                 target_kind: :dm,
                 target_id: message.id,
                 reason: "abuse"
               })

      assert report.target_kind == :dm
      assert report.target_id == message.id
    end
  end

  describe "account deletion" do
    test "anonymizes sent DMs and removes unread received DMs and DM notifications" do
      deleting = user_fixture()
      other = user_fixture()

      {:ok, sent} = DMs.send_message(deleting, other, %{body: "keep authored text"})
      {:ok, unread_received} = DMs.send_message(other, deleting, %{body: "remove unread inbox"})

      assert Notifications.unread_count(deleting) == 1
      assert {:ok, _deleted_user} = Accounts.delete_user(deleting)

      assert Repo.get!(Message, sent.id).sender_id == Accounts.tombstone_user_id()
      assert Repo.get(Message, unread_received.id) == nil
      assert Notifications.list_recent(deleting) == []
    end
  end
end
