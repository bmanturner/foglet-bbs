defmodule Foglet.Accounts.InviteTest do
  use FogletBbs.DataCase, async: false

  alias Foglet.Accounts.Invite

  describe "invite persistence foundation (INVT-02)" do
    test "Phase 2 invite generation cap dependency exists" do
      assert function_exported?(Foglet.Config, :invite_generation_per_user_limit, 0)
    end

    test "status/1 derives lifecycle state from persisted timestamps" do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      assert Invite.status(%Invite{}) == :available
      assert Invite.status(%Invite{consumed_at: now}) == :consumed
      assert Invite.status(%Invite{consumed_at: now, revoked_at: now}) == :revoked
      assert Invite.status(%Invite{revoked_at: now}) == :revoked
    end

    test "changeset validates generated public code shape" do
      assert Invite.changeset(%Invite{}, %{code: "INVITE1234567890"}).valid?

      refute Invite.changeset(%Invite{}, %{code: "short"}).valid?
      refute Invite.changeset(%Invite{}, %{code: "invite1234567890"}).valid?
      refute Invite.changeset(%Invite{}, %{code: String.duplicate("A", 65)}).valid?
    end
  end
end
