defmodule Foglet.Accounts.InviteTest do
  use FogletBbs.DataCase, async: false

  alias Foglet.Accounts
  alias Foglet.Accounts.Invite
  alias Foglet.Config
  alias FogletBbs.AccountsFixtures

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

  describe "create_invite/1 (INVT-02)" do
    setup :restore_invite_config

    test "creates an available invite for a sysop" do
      sysop = actor_fixture(:sysop)

      assert {:ok, %Invite{} = invite} = Accounts.create_invite(sysop)
      assert invite.issuer_id == sysop.id
      assert is_binary(invite.code)
      assert invite.code != ""
      assert Invite.status(invite) == :available
    end

    test "permits mods and users according to invite_code_generators policy" do
      sysop = actor_fixture(:sysop)
      mod = actor_fixture(:mod)
      user = AccountsFixtures.user_fixture()

      Config.put!("invite_code_generators", "sysop_only", sysop.id)
      assert {:ok, %Invite{}} = Accounts.create_invite(sysop)
      assert {:error, :forbidden} = Accounts.create_invite(mod)
      assert {:error, :forbidden} = Accounts.create_invite(user)

      Config.put!("invite_code_generators", "mods", sysop.id)
      assert {:ok, %Invite{}} = Accounts.create_invite(mod)
      assert {:error, :forbidden} = Accounts.create_invite(user)

      Config.put!("invite_code_generators", "any_user", sysop.id)
      assert {:ok, %Invite{}} = Accounts.create_invite(user)
    end

    test "enforces per-user generation cap only for any_user policy" do
      sysop = actor_fixture(:sysop)
      user = AccountsFixtures.user_fixture()

      Config.put!("invite_code_generators", "any_user", sysop.id)
      Config.put!("invite_generation_per_user_limit", 1, sysop.id)

      assert {:ok, %Invite{}} = Accounts.create_invite(user)
      assert {:error, :limit_reached} = Accounts.create_invite(user)

      Config.put!("invite_generation_per_user_limit", 0, sysop.id)
      assert {:ok, %Invite{}} = Accounts.create_invite(user)
      assert {:ok, %Invite{}} = Accounts.create_invite(user)
    end
  end

  describe "list_invites/1 (INVT-03)" do
    test "returns status rows with invite lifecycle fields" do
      sysop = actor_fixture(:sysop)
      invite = AccountsFixtures.invite_fixture(sysop)

      assert {:ok,
              [
                %{
                  code: code,
                  issuer_id: issuer_id,
                  inserted_at: %DateTime{},
                  consumed_at: nil,
                  consumed_by_user_id: nil,
                  revoked_at: nil,
                  status: :available
                }
              ]} = Accounts.list_invites(sysop)

      assert code == invite.code
      assert issuer_id == sysop.id
    end
  end

  describe "get_invite_status/1 (INVT-03)" do
    test "returns status map for existing invite code" do
      invite = AccountsFixtures.invite_fixture()

      assert {:ok, %{code: code, status: :available}} = Accounts.get_invite_status(invite.code)
      assert code == invite.code
    end

    test "returns not_found for unknown invite code" do
      assert {:error, :not_found} = Accounts.get_invite_status("UNKNOWNINVITECODE1")
    end
  end

  describe "revoke_invite/2 (INVT-04)" do
    test "revokes an available invite for a sysop" do
      sysop = actor_fixture(:sysop)
      invite = AccountsFixtures.invite_fixture(sysop)

      assert {:ok, %Invite{} = revoked} = Accounts.revoke_invite(sysop, invite.code)
      assert revoked.revoked_at != nil
      assert Invite.status(revoked) == :revoked
    end

    test "returns not_found for unknown invite code" do
      sysop = actor_fixture(:sysop)

      assert {:error, :not_found} = Accounts.revoke_invite(sysop, "UNKNOWNINVITECODE1")
    end

    test "returns unavailable for consumed invite" do
      sysop = actor_fixture(:sysop)
      user = AccountsFixtures.user_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
      invite = AccountsFixtures.invite_fixture(sysop)

      invite
      |> Ecto.Changeset.change(consumed_at: now, consumed_by_user_id: user.id)
      |> Repo.update!()

      assert {:error, :unavailable} = Accounts.revoke_invite(sysop, invite.code)
    end

    test "returns forbidden for unauthorized actors" do
      user = AccountsFixtures.user_fixture()
      invite = AccountsFixtures.invite_fixture()

      assert {:error, :forbidden} = Accounts.revoke_invite(user, invite.code)
    end
  end

  defp restore_invite_config(_context) do
    Config.init_cache()
    current_generators = Config.get("invite_code_generators", "sysops")
    current_limit = Config.get("invite_generation_per_user_limit", 0)

    on_exit(fn ->
      Config.put!("invite_code_generators", current_generators)
      Config.put!("invite_generation_per_user_limit", current_limit)
      Config.invalidate("invite_code_generators")
      Config.invalidate("invite_generation_per_user_limit")
    end)

    :ok
  end

  defp actor_fixture(role) do
    user = AccountsFixtures.user_fixture()
    {:ok, actor} = Accounts.update_role(user, role)
    actor
  end
end
