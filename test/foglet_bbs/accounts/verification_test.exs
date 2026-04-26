defmodule FogletBbs.VerificationTest.FailingMailerAdapter do
  def validate_config(_config), do: :ok
  def deliver(_email, _config), do: {:error, :forced_failure}
end

defmodule Foglet.Accounts.VerificationTest do
  use FogletBbs.DataCase, async: false

  alias Foglet.Accounts
  alias Foglet.Accounts.{User, UserToken, Verification}
  alias Foglet.Config
  alias FogletBbs.AccountsFixtures

  import Swoosh.TestAssertions

  describe "deliver_verification_code/1 (MAIL-02/MAIL-03)" do
    setup :set_swoosh_global

    setup do
      original_delivery_mode = Config.get("delivery_mode", "no_email")

      on_exit(fn ->
        Config.put!("delivery_mode", original_delivery_mode)
        Config.invalidate("delivery_mode")
      end)

      :ok
    end

    test "email mode persists an email_verify token and attempts delivery" do
      Config.put!("delivery_mode", "email")
      user = AccountsFixtures.user_fixture(%{handle: "verifyme", email: "verifyme@example.test"})

      assert {:ok, :attempted} = Verification.deliver_verification_code(user)

      assert Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "email_verify"
             )

      assert_email_sent(fn email ->
        assert email.to == [{"verifyme", "verifyme@example.test"}]
        assert email.subject == "Your Foglet verification code"
        assert email.text_body =~ "Return to your SSH terminal session"
      end)
    end

    test "no-email mode returns unavailable without creating a token or email" do
      Config.put!("delivery_mode", "no_email")
      user = AccountsFixtures.user_fixture()

      assert {:error, :unavailable} = Verification.deliver_verification_code(user)

      refute Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "email_verify"
             )

      refute_email_sent()
    end
  end

  describe "request_password_reset_delivery/1 (MAIL-04/MAIL-05)" do
    setup :set_swoosh_global

    setup do
      original_delivery_mode = Config.get("delivery_mode", "no_email")
      original_mailer_config = Application.fetch_env!(:foglet_bbs, Foglet.Mailer)

      on_exit(fn ->
        Config.put!("delivery_mode", original_delivery_mode)
        Config.invalidate("delivery_mode")
        Application.put_env(:foglet_bbs, Foglet.Mailer, original_mailer_config)
      end)

      :ok
    end

    test "email mode returns a generic response and delivers for an active handle match" do
      Config.put!("delivery_mode", "email")
      user = AccountsFixtures.user_fixture(%{handle: "resetme", email: "resetme@example.test"})

      assert {:ok, :generic_response} =
               Verification.request_password_reset_delivery("  resetme  ")

      assert Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "reset_password"
             )

      assert_email_sent(fn email ->
        assert email.to == [{"resetme", "resetme@example.test"}]
        assert email.subject == "Foglet password reset instructions"
        assert email.text_body =~ "Return to the SSH terminal reset flow"
        refute email.text_body =~ "/users/reset_password"
        refute email.text_body =~ "http://"
        refute email.text_body =~ "https://"
        true
      end)
    end

    test "email mode returns a generic response and delivers for an active email match" do
      Config.put!("delivery_mode", "email")

      user =
        AccountsFixtures.user_fixture(%{handle: "emailreset", email: "emailreset@example.test"})

      assert {:ok, :generic_response} =
               Verification.request_password_reset_delivery("emailreset@example.test")

      assert Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "reset_password"
             )

      assert_email_sent()
    end

    test "email mode returns the same generic response for unknown, deleted, pending, and suspended users" do
      Config.put!("delivery_mode", "email")
      deleted = AccountsFixtures.user_fixture(%{handle: "deletedreset"})
      {:ok, _deleted} = Accounts.delete_user(deleted)

      pending =
        AccountsFixtures.user_fixture(%{handle: "pendingreset"})
        |> User.status_changeset(%{status: :pending})
        |> Repo.update!()

      suspended =
        AccountsFixtures.user_fixture(%{handle: "suspendedreset"})
        |> User.status_changeset(%{status: :suspended})
        |> Repo.update!()

      for identifier <- ["nobody", deleted.handle, pending.handle, suspended.handle] do
        assert {:ok, :generic_response} =
                 Verification.request_password_reset_delivery(identifier)
      end

      for user <- [deleted, pending, suspended] do
        refute Repo.exists?(
                 from t in UserToken,
                   where: t.user_id == ^user.id and t.context == "reset_password"
               )
      end

      refute_email_sent()
    end

    test "email mode returns the same generic response when delivery fails" do
      Config.put!("delivery_mode", "email")

      Application.put_env(:foglet_bbs, Foglet.Mailer,
        adapter: FogletBbs.VerificationTest.FailingMailerAdapter
      )

      user = AccountsFixtures.user_fixture(%{handle: "failreset"})

      assert {:ok, :generic_response} = Verification.request_password_reset_delivery("failreset")

      assert Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "reset_password"
             )
    end

    test "no-email mode returns unavailable without lookup side effects" do
      Config.put!("delivery_mode", "no_email")
      user = AccountsFixtures.user_fixture(%{handle: "noemailreset"})

      assert {:error, :unavailable} =
               Verification.request_password_reset_delivery("noemailreset")

      refute Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "reset_password"
             )

      refute_email_sent()
    end
  end

  describe "reset_user_password/2 (IDNT-08)" do
    test "updates password and invalidates outstanding reset tokens" do
      user = AccountsFixtures.user_fixture(%{password: "original1"})
      {_raw, _} = AccountsFixtures.user_token_fixture(user, "reset_password")

      assert Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "reset_password"
             )

      assert {:ok, updated} = Verification.reset_user_password(user, %{password: "brandnew1"})
      assert Argon2.verify_pass("brandnew1", updated.password_hash)
      refute Argon2.verify_pass("original1", updated.password_hash)

      refute Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "reset_password"
             )
    end
  end
end
