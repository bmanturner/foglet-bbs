defmodule Foglet.NotificationsTest do
  use FogletBbs.DataCase, async: true

  import Ecto.Query

  alias Foglet.Accounts
  alias Foglet.Notifications
  alias Foglet.Notifications.Notification
  alias Foglet.PubSub, as: Topics
  alias FogletBbs.AccountsFixtures

  describe "create_notification/1" do
    test "creates a notification, sanitizes payload snippets, and broadcasts" do
      recipient = AccountsFixtures.user_fixture()
      actor = AccountsFixtures.user_fixture()

      :ok = Phoenix.PubSub.subscribe(FogletBbs.PubSub, Topics.notifications_topic(recipient.id))

      assert {:ok, %Notification{} = notification} =
               Notifications.create_notification(%{
                 user_id: recipient.id,
                 actor_id: actor.id,
                 kind: :reply,
                 payload: %{
                   board_id: Ecto.UUID.generate(),
                   thread_id: Ecto.UUID.generate(),
                   post_id: Ecto.UUID.generate(),
                   snippet: "  hello\n\nworld  "
                 }
               })

      assert notification.user_id == recipient.id
      assert notification.actor_id == actor.id
      assert notification.kind == :reply
      notification_id = notification.id
      recipient_id = recipient.id

      assert notification.payload["snippet"] == "hello world"
      assert Notifications.unread_count(recipient) == 1

      assert_receive {:notifications, :created,
                      %Notification{id: ^notification_id, user_id: ^recipient_id}},
                     500
    end

    test "validates payload shape for the notification kind" do
      recipient = AccountsFixtures.user_fixture()

      assert {:error, changeset} =
               Notifications.create_notification(%{
                 user_id: recipient.id,
                 kind: :mention,
                 payload: %{
                   board_id: Ecto.UUID.generate(),
                   post_id: Ecto.UUID.generate()
                 }
               })

      assert "is invalid" in errors_on(changeset).payload
    end

    test "supports idempotent dedupe keys per recipient" do
      recipient = AccountsFixtures.user_fixture()
      actor = AccountsFixtures.user_fixture()
      dedupe_key = "reply:" <> Ecto.UUID.generate()

      attrs = %{
        user_id: recipient.id,
        actor_id: actor.id,
        kind: :reply,
        dedupe_key: dedupe_key,
        payload: %{
          board_id: Ecto.UUID.generate(),
          thread_id: Ecto.UUID.generate(),
          post_id: Ecto.UUID.generate(),
          snippet: "first"
        }
      }

      assert {:ok, %Notification{id: id1}} = Notifications.create_notification(attrs)
      assert {:ok, %Notification{id: id2}} = Notifications.create_notification(attrs)
      assert id1 == id2

      assert Repo.aggregate(
               from(n in Notification,
                 where: n.user_id == ^recipient.id and n.dedupe_key == ^dedupe_key
               ),
               :count
             ) == 1
    end

    test "allows nil actors and survives deleted actors in recent inbox queries" do
      recipient = AccountsFixtures.user_fixture()
      deleted_actor = AccountsFixtures.user_fixture()

      assert {:ok, %Notification{id: nil_actor_id}} =
               Notifications.create_notification(%{
                 user_id: recipient.id,
                 kind: :thread_update,
                 payload: %{
                   thread_id: Ecto.UUID.generate(),
                   new_post_ids: [Ecto.UUID.generate()]
                 }
               })

      assert {:ok, %Notification{id: deleted_actor_notification_id}} =
               Notifications.create_notification(%{
                 user_id: recipient.id,
                 actor_id: deleted_actor.id,
                 kind: :reply,
                 payload: %{
                   board_id: Ecto.UUID.generate(),
                   thread_id: Ecto.UUID.generate(),
                   post_id: Ecto.UUID.generate(),
                   snippet: "still here"
                 }
               })

      assert {:ok, _deleted_actor} = Accounts.delete_user(deleted_actor)

      recent = Notifications.list_recent(recipient, 10)

      assert Enum.any?(
               recent,
               &(&1.id == nil_actor_id and is_nil(&1.actor_id) and is_nil(&1.actor))
             )

      assert Enum.any?(recent, fn notification ->
               notification.id == deleted_actor_notification_id and
                 notification.actor_id == deleted_actor.id and
                 match?(%Foglet.Accounts.User{deleted_at: %DateTime{}}, notification.actor)
             end)
    end
  end

  describe "list_recent/2" do
    test "returns newest notifications first" do
      recipient = AccountsFixtures.user_fixture()

      first = notification_fixture!(recipient, %{payload: mention_payload("first")})
      second = notification_fixture!(recipient, %{payload: mention_payload("second")})
      third = notification_fixture!(recipient, %{payload: mention_payload("third")})

      set_inserted_at!(first, ~U[2026-05-11 21:00:00.000001Z])
      set_inserted_at!(second, ~U[2026-05-11 21:00:01.000001Z])
      set_inserted_at!(third, ~U[2026-05-11 21:00:02.000001Z])

      assert Notifications.list_recent(recipient, 2)
             |> Enum.map(& &1.payload["snippet"]) == ["third", "second"]
    end
  end

  describe "mark_read/2" do
    test "marks one notification read, updates unread count, and broadcasts" do
      recipient = AccountsFixtures.user_fixture()
      notification = notification_fixture!(recipient)

      :ok = Phoenix.PubSub.subscribe(FogletBbs.PubSub, Topics.notifications_topic(recipient.id))

      notification_id = notification.id
      recipient_id = recipient.id

      assert {:ok, %Notification{id: ^notification_id, read_at: %DateTime{} = read_at}} =
               Notifications.mark_read(recipient, notification.id)

      assert read_at == Repo.get!(Notification, notification.id).read_at
      assert Notifications.unread_count(recipient) == 0

      assert_receive {:notifications, :read,
                      %{notification_id: ^notification_id, user_id: ^recipient_id}},
                     500
    end
  end

  describe "mark_all_read/1" do
    test "marks only unread notifications read and broadcasts the affected count" do
      recipient = AccountsFixtures.user_fixture()
      unread_one = notification_fixture!(recipient)
      unread_two = notification_fixture!(recipient)
      already_read = notification_fixture!(recipient, %{read_at: ~U[2026-05-11 20:59:00.000000Z]})

      :ok = Phoenix.PubSub.subscribe(FogletBbs.PubSub, Topics.notifications_topic(recipient.id))

      recipient_id = recipient.id

      assert {:ok, 2} = Notifications.mark_all_read(recipient)

      assert Repo.get!(Notification, unread_one.id).read_at
      assert Repo.get!(Notification, unread_two.id).read_at
      assert Repo.get!(Notification, already_read.id).read_at == already_read.read_at
      assert Notifications.unread_count(recipient) == 0

      assert_receive {:notifications, :all_read, %{user_id: ^recipient_id, count: 2}}, 500
    end
  end

  describe "Foglet.PubSub topic helpers" do
    test "notifications_topic/1 produces a stable user-scoped topic" do
      assert Topics.notifications_topic("abc") == "notifications:abc"
      refute Topics.notifications_topic("abc") == Topics.notifications_topic("xyz")
    end
  end

  defp notification_fixture!(recipient, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          user_id: recipient.id,
          kind: :mention,
          payload: mention_payload("fixture")
        },
        attrs
      )

    {:ok, notification} = Notifications.create_notification(attrs)
    notification
  end

  defp mention_payload(snippet) do
    %{
      board_id: Ecto.UUID.generate(),
      thread_id: Ecto.UUID.generate(),
      post_id: Ecto.UUID.generate(),
      snippet: snippet
    }
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
