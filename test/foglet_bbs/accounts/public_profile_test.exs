defmodule Foglet.Accounts.PublicProfileTest do
  use ExUnit.Case, async: true

  alias Foglet.Accounts.PublicProfile
  alias Foglet.Sessions.PresenceSummary

  defmodule OfflineSessions do
    def lookup_session(_user_id), do: {:error, :not_found}
  end

  test "from_user/2 whitelists public profile fields and excludes private/operator fields" do
    user = %{
      id: "u1",
      handle: "alice",
      role: :sysop,
      tagline: "Terminal local",
      location: "The Grid",
      post_count: 42,
      inserted_at: ~U[2026-04-01 00:00:00Z],
      last_seen_at: ~U[2026-04-02 00:00:00Z],
      real_name: "Private Name",
      email: "alice@example.test",
      password_hash: "secret",
      confirmed_at: ~U[2026-04-01 00:00:00Z]
    }

    profile = PublicProfile.from_user(user, sessions: OfflineSessions)

    assert %PublicProfile{
             user_id: "u1",
             handle: "alice",
             role: :sysop,
             tagline: "Terminal local",
             location: "The Grid",
             post_count: 42,
             presence: %PresenceSummary{activity: :offline, online?: false}
           } = profile

    refute Map.has_key?(profile, :real_name)
    refute Map.has_key?(profile, :email)
    refute Map.has_key?(profile, :password_hash)
    refute Map.has_key?(profile, :confirmed_at)
  end
end
