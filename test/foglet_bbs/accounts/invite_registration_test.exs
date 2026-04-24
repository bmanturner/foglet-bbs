defmodule Foglet.Accounts.InviteRegistrationTest do
  use FogletBbs.DataCase, async: false

  alias Foglet.Accounts
  alias Foglet.Accounts.Invite
  alias Foglet.Config
  alias FogletBbs.AccountsFixtures

  describe "invite_only registration (INVT-05)" do
    setup :force_invite_only_registration

    test "missing invite_code returns a changeset error" do
      attrs = AccountsFixtures.valid_user_attributes()

      assert {:error, changeset} = Accounts.register_user(attrs)
      assert errors_on(changeset).invite_code
    end

    test "unknown, revoked, and consumed codes return the same generic invite_code error" do
      issuer = actor_fixture(:sysop)
      user = with_open_registration(fn -> AccountsFixtures.user_fixture() end)
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      revoked =
        issuer
        |> AccountsFixtures.invite_fixture()
        |> Ecto.Changeset.change(revoked_at: now)
        |> Repo.update!()

      consumed =
        issuer
        |> AccountsFixtures.invite_fixture()
        |> Ecto.Changeset.change(consumed_at: now, consumed_by_user_id: user.id)
        |> Repo.update!()

      unknown_errors = registration_errors("UNKNOWNINVITECODE1")
      revoked_errors = registration_errors(revoked.code)
      consumed_errors = registration_errors(consumed.code)

      assert unknown_errors == revoked_errors
      assert revoked_errors == consumed_errors
      assert unknown_errors.invite_code
    end

    test "successful registration consumes the invite" do
      invite = with_open_registration(fn -> AccountsFixtures.invite_fixture() end)
      attrs = AccountsFixtures.valid_user_attributes(%{invite_code: invite.code})

      assert {:ok, user} = Accounts.register_user(attrs)

      reloaded = Repo.get!(Invite, invite.id)
      assert reloaded.consumed_at != nil
      assert reloaded.consumed_by_user_id == user.id
      assert Invite.status(reloaded) == :consumed
    end

    test "invalid user attrs leave an available invite unconsumed" do
      invite = with_open_registration(fn -> AccountsFixtures.invite_fixture() end)

      attrs =
        AccountsFixtures.valid_user_attributes(%{
          invite_code: invite.code,
          email: "not-an-email"
        })

      assert {:error, changeset} = Accounts.register_user(attrs)
      assert errors_on(changeset).email

      reloaded = Repo.get!(Invite, invite.id)
      assert Invite.status(reloaded) == :available
      assert reloaded.consumed_at == nil
      assert reloaded.consumed_by_user_id == nil
    end

    test "second redemption cannot create a second user" do
      invite = with_open_registration(fn -> AccountsFixtures.invite_fixture() end)

      first_attrs = AccountsFixtures.valid_user_attributes(%{invite_code: invite.code})
      second_attrs = AccountsFixtures.valid_user_attributes(%{invite_code: invite.code})

      assert {:ok, _user} = Accounts.register_user(first_attrs)
      assert {:error, changeset} = Accounts.register_user(second_attrs)
      assert errors_on(changeset).invite_code
    end
  end

  defp registration_errors(code) do
    attrs = AccountsFixtures.valid_user_attributes(%{invite_code: code})
    assert {:error, changeset} = Accounts.register_user(attrs)
    errors_on(changeset)
  end

  defp force_invite_only_registration(_context) do
    Config.init_cache()
    current_registration_mode = Config.get("registration_mode", "open")
    Config.put!("registration_mode", "invite_only")

    on_exit(fn ->
      Config.put!("registration_mode", current_registration_mode)
      Config.invalidate("registration_mode")
    end)

    :ok
  end

  defp actor_fixture(role) do
    user = with_open_registration(fn -> AccountsFixtures.user_fixture() end)
    {:ok, actor} = Accounts.update_role(user, role)
    actor
  end

  defp with_open_registration(fun) do
    current_registration_mode = Config.get("registration_mode", "open")
    Config.put!("registration_mode", "open")

    try do
      fun.()
    after
      Config.put!("registration_mode", current_registration_mode)
      Config.invalidate("registration_mode")
    end
  end
end
