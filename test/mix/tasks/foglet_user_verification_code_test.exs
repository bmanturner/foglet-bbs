defmodule Mix.Tasks.Foglet.User.VerificationCodeTest do
  use FogletBbs.DataCase, async: false

  import ExUnit.CaptureIO
  import Ecto.Query

  alias Foglet.Accounts
  alias Foglet.Accounts.UserToken
  alias Foglet.Config
  alias FogletBbs.AccountsFixtures

  setup do
    original_delivery_mode = Config.get("delivery_mode", "no_email")

    on_exit(fn ->
      Config.put!("delivery_mode", original_delivery_mode, nil)
      Config.invalidate("delivery_mode")
    end)

    Mix.shell(Mix.Shell.IO)
    :ok
  end

  describe "mix foglet.user.verification_code" do
    test "in no-email mode prints a fresh operator verification code" do
      Config.put!("delivery_mode", "no_email", nil)
      user = AccountsFixtures.user_fixture(%{handle: "verifytask"})

      output =
        capture_io(fn ->
          Mix.Tasks.Foglet.User.VerificationCode.run([user.handle])
        end)

      assert output =~ "No-email verification code for verifytask:"

      assert output =~
               "This verification code was generated for operator retrieval; no email was sent by this task."

      [code] = Regex.run(~r/\n  ([A-Z0-9]{6})\n/, output, capture: :all_but_first)
      assert code =~ ~r/\A[A-Z0-9]{6}\z/

      assert Repo.exists?(
               from t in UserToken,
                 where:
                   t.user_id == ^user.id and t.context == "email_verify" and
                     t.token == ^code
             )
    end

    test "in email mode exits non-zero without creating a token" do
      Config.put!("delivery_mode", "email", nil)
      user = AccountsFixtures.user_fixture(%{handle: "emailverifytask"})

      output =
        capture_io(:stderr, fn ->
          assert catch_exit(Mix.Tasks.Foglet.User.VerificationCode.run([user.handle])) ==
                   {:shutdown, 1}
        end)

      assert output =~
               "Verification delivery is handled by email mode; use the normal Login or Verify resend flow."

      refute Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "email_verify"
             )
    end

    test "confirmed users are rejected" do
      Config.put!("delivery_mode", "no_email", nil)
      user = AccountsFixtures.user_fixture(%{handle: "confirmedtask"})

      confirmed =
        user
        |> Ecto.Changeset.change(%{confirmed_at: DateTime.utc_now()})
        |> Repo.update!()

      output =
        capture_io(:stderr, fn ->
          assert catch_exit(Mix.Tasks.Foglet.User.VerificationCode.run([confirmed.handle])) ==
                   {:shutdown, 1}
        end)

      assert output =~ "already confirmed"
    end

    test "deleted users are rejected" do
      Config.put!("delivery_mode", "no_email", nil)
      user = AccountsFixtures.user_fixture(%{handle: "deletedverifytask"})
      {:ok, _} = Accounts.delete_user(user)

      output =
        capture_io(:stderr, fn ->
          assert catch_exit(Mix.Tasks.Foglet.User.VerificationCode.run(["deletedverifytask"])) ==
                   {:shutdown, 1}
        end)

      assert output =~ "deleted" or output =~ "User not found"
    end

    test "unknown handle exits non-zero" do
      Config.put!("delivery_mode", "no_email", nil)

      output =
        capture_io(:stderr, fn ->
          assert catch_exit(Mix.Tasks.Foglet.User.VerificationCode.run(["no_such_user"])) ==
                   {:shutdown, 1}
        end)

      assert output =~ "User not found"
    end

    test "missing handle exits non-zero" do
      capture_io(:stderr, fn ->
        assert catch_exit(Mix.Tasks.Foglet.User.VerificationCode.run([])) == {:shutdown, 1}
      end)
    end

    test "unknown flag exits non-zero" do
      capture_io(:stderr, fn ->
        assert catch_exit(Mix.Tasks.Foglet.User.VerificationCode.run(["foo", "--bogus", "x"])) ==
                 {:shutdown, 1}
      end)
    end
  end
end
