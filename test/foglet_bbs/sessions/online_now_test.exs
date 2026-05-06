defmodule Foglet.Sessions.OnlineNowTest do
  use ExUnit.Case, async: true

  alias Foglet.Sessions.OnlineNow
  alias Foglet.Sessions.PresenceSummary

  defmodule FakeSessions do
    def online_user_ids, do: ["u2", nil, "u1", "u2", "guestless"]
  end

  defmodule FakeAccounts do
    def get_user("u1"), do: %{id: "u1", handle: "alice", role: :user}
    def get_user("u2"), do: %{id: "u2", handle: "zoe", role: :mod}
    def get_user("guestless"), do: nil
  end

  defmodule FakePresence do
    def for_user("u1", _opts),
      do: %PresenceSummary{activity: :online, label: "Online", online?: true}

    def for_user("u2", _opts),
      do: %PresenceSummary{activity: :online, label: "Browsing general", online?: true}
  end

  test "count uses unique authenticated registry ids and excludes nil guest ids" do
    assert OnlineNow.count(sessions: FakeSessions) == 3
  end

  test "list loads public user rows, reuses presence labels, and sorts deterministically" do
    assert [zoe, alice] =
             OnlineNow.list(
               sessions: FakeSessions,
               accounts: FakeAccounts,
               presence: FakePresence
             )

    assert zoe.user_id == "u2"
    assert zoe.handle == "zoe"
    assert zoe.role == :mod
    assert zoe.presence_label == "Browsing general"
    assert zoe.user == %{id: "u2", handle: "zoe", role: :mod}

    assert alice.user_id == "u1"
    assert alice.handle == "alice"
    assert alice.role == :user
    assert alice.presence_label == "Online"
  end
end
