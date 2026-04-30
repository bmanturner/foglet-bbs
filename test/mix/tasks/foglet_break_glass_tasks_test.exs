defmodule Mix.Tasks.FogletBreakGlassTasksTest do
  use FogletBbs.DataCase, async: false

  import Ecto.Query
  import ExUnit.CaptureIO

  alias Foglet.Accounts
  alias Foglet.Accounts.{Invite, User, UserToken, Verification}
  alias Foglet.Config
  alias FogletBbs.AccountsFixtures

  setup do
    Config.init_cache()

    original_registration_mode = Config.get("registration_mode", "open")
    original_require_email_verification = Config.get("require_email_verification", false)
    original_delivery_mode = Config.get("delivery_mode", "no_email")
    original_invite_generators = Config.get("invite_code_generators", "sysop_only")

    on_exit(fn ->
      Config.put!("registration_mode", original_registration_mode, nil)
      Config.put!("require_email_verification", original_require_email_verification, nil)
      Config.put!("delivery_mode", original_delivery_mode, nil)
      Config.put!("invite_code_generators", original_invite_generators, nil)
      Config.invalidate("registration_mode")
      Config.invalidate("require_email_verification")
      Config.invalidate("delivery_mode")
      Config.invalidate("invite_code_generators")
    end)

    Mix.shell(Mix.Shell.IO)
    :ok
  end

  describe "mix foglet.invites.*" do
    test "create persists an available invite through actor authorization" do
      sysop = sysop_fixture("invitesysop")

      output =
        capture_io(fn ->
          Mix.Tasks.Foglet.Invites.Create.run(["--actor", sysop.handle])
        end)

      [code] = Regex.run(~r/\n  ([A-Z0-9]{16,64})\n/, output, capture: :all_but_first)

      assert %Invite{issuer_id: issuer_id, revoked_at: nil, consumed_at: nil} =
               Repo.get_by(Invite, code: code)

      assert issuer_id == sysop.id
    end

    test "list and inspect require an authorized actor and expose persisted lifecycle state" do
      sysop = sysop_fixture("inspectsysop")
      invite = AccountsFixtures.invite_fixture(sysop)

      list_output =
        capture_io(fn ->
          Mix.Tasks.Foglet.Invites.List.run(["--actor", sysop.handle])
        end)

      assert list_output =~ "code=#{invite.code}"
      assert list_output =~ "status=available"

      inspect_output =
        capture_io(fn ->
          Mix.Tasks.Foglet.Invites.Inspect.run([invite.code, "--actor", sysop.handle])
        end)

      assert inspect_output =~ "Invite code: #{invite.code}"
      assert inspect_output =~ "Status: available"
    end

    test "revoke only revokes available invite codes" do
      sysop = sysop_fixture("revokesysop")
      invite = AccountsFixtures.invite_fixture(sysop)

      capture_io(fn ->
        Mix.Tasks.Foglet.Invites.Revoke.run([invite.code, "--actor", sysop.handle])
      end)

      assert %Invite{} = revoked = Repo.get!(Invite, invite.id)
      assert Invite.status(revoked) == :revoked
    end

    test "unauthorized invite create exits without persisting an invite" do
      user = AccountsFixtures.user_fixture(%{handle: "regularinviteactor"})
      before_count = Repo.aggregate(Invite, :count)

      capture_io(:stderr, fn ->
        assert catch_exit(Mix.Tasks.Foglet.Invites.Create.run(["--actor", user.handle])) ==
                 {:shutdown, 1}
      end)

      assert Repo.aggregate(Invite, :count) == before_count
    end
  end

  describe "mix foglet.verification.inspect" do
    test "prints the latest unexpired no-email verification code without creating a new code" do
      Config.put!("delivery_mode", "no_email", nil)
      user = AccountsFixtures.user_fixture(%{handle: "verifyinspect"})
      assert {:ok, older_code} = Verification.build_verify_code(user)
      assert {:ok, latest_code} = Verification.build_verify_code(user)

      output =
        capture_io(fn ->
          Mix.Tasks.Foglet.Verification.Inspect.run([user.handle])
        end)

      assert output =~ latest_code
      refute output =~ older_code

      assert Repo.aggregate(
               from(t in UserToken,
                 where: t.user_id == ^user.id and t.context == "email_verify"
               ),
               :count
             ) == 2
    end

    test "email mode refuses verification DB inspection" do
      Config.put!("delivery_mode", "email", nil)
      user = AccountsFixtures.user_fixture(%{handle: "emailinspect"})
      assert {:ok, _code} = Verification.build_verify_code(user)

      output =
        capture_io(:stderr, fn ->
          assert catch_exit(Mix.Tasks.Foglet.Verification.Inspect.run([user.handle])) ==
                   {:shutdown, 1}
        end)

      assert output =~ "only available when delivery_mode is no_email"
    end
  end

  describe "mix foglet.reset_token.inspect" do
    test "no-email mode prints a fresh raw reset token and stores only its hash" do
      Config.put!("delivery_mode", "no_email", nil)
      user = AccountsFixtures.user_fixture(%{handle: "resetinspect"})

      output =
        capture_io(fn ->
          Mix.Tasks.Foglet.ResetToken.Inspect.run([user.handle])
        end)

      [_, raw_token] = Regex.run(~r/Reset token: ([A-Za-z0-9_-]+)/, output)
      {:ok, decoded_token} = Base.url_decode64(raw_token, padding: false)
      hashed_token = :crypto.hash(UserToken.hash_algorithm(), decoded_token)

      assert Repo.exists?(
               from t in UserToken,
                 where:
                   t.user_id == ^user.id and t.context == "reset_password" and
                     t.token == ^hashed_token
             )

      refute Repo.exists?(
               from t in UserToken,
                 where:
                   t.user_id == ^user.id and t.context == "reset_password" and
                     t.token == ^raw_token
             )
    end

    test "email mode refuses reset token inspection" do
      Config.put!("delivery_mode", "email", nil)
      user = AccountsFixtures.user_fixture(%{handle: "emailresetinspect"})

      output =
        capture_io(:stderr, fn ->
          assert catch_exit(Mix.Tasks.Foglet.ResetToken.Inspect.run([user.handle])) ==
                   {:shutdown, 1}
        end)

      assert output =~ "only available when delivery_mode is no_email"
    end

    test "expire backdates the latest reset token outside the validity window" do
      Config.put!("delivery_mode", "no_email", nil)
      user = AccountsFixtures.user_fixture(%{handle: "expiretoken"})

      capture_io(fn ->
        Mix.Tasks.Foglet.ResetToken.Inspect.run([user.handle])
      end)

      capture_io(fn ->
        Mix.Tasks.Foglet.ResetToken.Expire.run([user.handle])
      end)

      token =
        Repo.one!(
          from t in UserToken,
            where: t.user_id == ^user.id and t.context == "reset_password",
            order_by: [desc: t.inserted_at],
            limit: 1
        )

      assert DateTime.diff(DateTime.utc_now(), token.inserted_at, :day) >
               UserToken.validity_days("reset_password")
    end
  end

  describe "mix foglet.qa.mode" do
    test "updates selected QA matrix config keys through schema validation" do
      output =
        capture_io(fn ->
          Mix.Tasks.Foglet.Qa.Mode.run([
            "--registration-mode",
            "invite_only",
            "--require-email-verification",
            "true",
            "--delivery-mode",
            "email"
          ])
        end)

      assert output =~ "QA mode updated:"
      assert Config.registration_mode() == "invite_only"
      assert Config.require_email_verification?() == true
      assert Config.delivery_mode() == "email"
    end

    test "rejects invalid registration mode without changing config" do
      Config.put!("registration_mode", "open", nil)

      output =
        capture_io(:stderr, fn ->
          assert catch_exit(Mix.Tasks.Foglet.Qa.Mode.run(["--registration-mode", "disabled"])) ==
                   {:shutdown, 1}
        end)

      assert output =~ "registration_mode"
      assert Config.registration_mode() == "open"
    end
  end

  describe "mix foglet.users.approve/reject" do
    test "approve activates a pending user through the Accounts status transition" do
      sysop = sysop_fixture("approvesysop")
      pending = pending_user_fixture("pendingapprove")

      capture_io(fn ->
        Mix.Tasks.Foglet.Users.Approve.run([pending.handle, "--actor", sysop.handle])
      end)

      assert Accounts.get_user_by_handle(pending.handle).status == :active
    end

    test "reject rejects a pending user through the Accounts status transition" do
      sysop = sysop_fixture("rejectsysop")
      pending = pending_user_fixture("pendingreject")

      capture_io(fn ->
        Mix.Tasks.Foglet.Users.Reject.run([pending.handle, "--actor", sysop.handle])
      end)

      assert Accounts.get_user_by_handle(pending.handle).status == :rejected
    end

    test "approve rejects unauthorized actors before mutating the target" do
      actor = AccountsFixtures.user_fixture(%{handle: "approveuseractor"})
      pending = pending_user_fixture("pendingforbidden")

      capture_io(:stderr, fn ->
        assert catch_exit(
                 Mix.Tasks.Foglet.Users.Approve.run([pending.handle, "--actor", actor.handle])
               ) == {:shutdown, 1}
      end)

      assert Accounts.get_user_by_handle(pending.handle).status == :pending
    end
  end

  defp sysop_fixture(handle) do
    user = AccountsFixtures.user_fixture(%{handle: handle})
    {:ok, sysop} = Accounts.update_role(user, :sysop)
    sysop
  end

  defp pending_user_fixture(handle) do
    AccountsFixtures.user_fixture(%{handle: handle})
    |> User.status_changeset(%{status: :pending})
    |> Repo.update!()
  end
end
