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

  import ExUnit.CaptureLog
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

    test "email delivery failure logs useful non-sensitive context" do
      Config.put!("delivery_mode", "email")

      original_mailer_config = Application.fetch_env!(:foglet_bbs, Foglet.Mailer)

      on_exit(fn ->
        Application.put_env(:foglet_bbs, Foglet.Mailer, original_mailer_config)
      end)

      Application.put_env(:foglet_bbs, Foglet.Mailer,
        adapter: FogletBbs.VerificationTest.FailingMailerAdapter
      )

      user =
        AccountsFixtures.user_fixture(%{
          handle: "verifylog",
          email: "verifylog@example.test"
        })

      log =
        capture_log(fn ->
          assert {:error, :delivery_failed} = Verification.deliver_verification_code(user)
        end)

      assert log =~ "transactional_email_delivery_failed"
      assert log =~ "mail_type=verification_code"
      assert log =~ "delivery_mode=email"
      assert log =~ "recipient_user_id=#{user.id}"
      assert log =~ "reason=:forced_failure"
      refute log =~ user.email
      refute log =~ user.handle
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

    test "email mode does not create a reset_password token for a handle-only identifier" do
      # D-02/D-03: handle-only reset requests no longer create a token.
      # The reset request path is email-only at the boundary level too.
      Config.put!("delivery_mode", "email")
      user = AccountsFixtures.user_fixture(%{handle: "resetme", email: "resetme@example.test"})

      assert {:ok, :generic_response} =
               Verification.request_password_reset_delivery("  resetme  ")

      refute Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "reset_password"
             )

      refute_email_sent()
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

      assert_email_sent(fn email ->
        assert email.to == [{"emailreset", "emailreset@example.test"}]
        assert email.subject == "Foglet password reset instructions"
        assert email.text_body =~ "Return to the SSH terminal reset flow"
        refute email.text_body =~ "/users/reset_password"
        refute email.text_body =~ "http://"
        refute email.text_body =~ "https://"
        true
      end)
    end

    test "email mode returns the same generic response for unknown, deleted, pending, suspended, and rejected emails without creating tokens" do
      # D-03/D-16: valid email-shaped submissions for unknown, deleted, pending,
      # suspended, and rejected accounts return the same generic response and
      # create no reset_password token rows.
      Config.put!("delivery_mode", "email")

      deleted =
        AccountsFixtures.user_fixture(%{
          handle: "deletedreset",
          email: "deletedreset@example.test"
        })

      {:ok, _deleted} = Accounts.delete_user(deleted)

      pending =
        AccountsFixtures.user_fixture(%{
          handle: "pendingreset",
          email: "pendingreset@example.test"
        })
        |> User.status_changeset(%{status: :pending})
        |> Repo.update!()

      suspended =
        AccountsFixtures.user_fixture(%{
          handle: "suspendedreset",
          email: "suspendedreset@example.test"
        })
        |> User.status_changeset(%{status: :suspended})
        |> Repo.update!()

      rejected =
        AccountsFixtures.user_fixture(%{
          handle: "rejectedreset",
          email: "rejectedreset@example.test"
        })
        |> User.status_changeset(%{status: :rejected})
        |> Repo.update!()

      identifiers = [
        "nobody@example.test",
        # original (pre-deletion) email — deleted_user.email is rewritten by
        # deletion_changeset to deleted-<id>@localhost, so this shape no longer
        # matches anything in the DB.
        "deletedreset@example.test",
        pending.email,
        suspended.email,
        rejected.email
      ]

      for identifier <- identifiers do
        assert {:ok, :generic_response} =
                 Verification.request_password_reset_delivery(identifier)
      end

      for user <- [pending, suspended, rejected] do
        refute Repo.exists?(
                 from t in UserToken,
                   where: t.user_id == ^user.id and t.context == "reset_password"
               )
      end

      # Deleted user's email was rewritten on anonymization; assert no
      # reset_password token exists for that user_id either.
      refute Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^deleted.id and t.context == "reset_password"
             )

      refute_email_sent()
    end

    test "email mode returns the same generic response and logs non-sensitive context when delivery fails" do
      Config.put!("delivery_mode", "email")

      Application.put_env(:foglet_bbs, Foglet.Mailer,
        adapter: FogletBbs.VerificationTest.FailingMailerAdapter
      )

      user =
        AccountsFixtures.user_fixture(%{handle: "failreset", email: "failreset@example.test"})

      log =
        capture_log(fn ->
          assert {:ok, :generic_response} =
                   Verification.request_password_reset_delivery("failreset@example.test")
        end)

      assert log =~ "transactional_email_delivery_failed"
      assert log =~ "mail_type=password_reset"
      assert log =~ "delivery_mode=email"
      assert log =~ "recipient_user_id=#{user.id}"
      assert log =~ "reason=:forced_failure"
      refute log =~ user.email
      refute log =~ user.handle

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

  describe "active_sysop_contact_emails/0 (D-13/D-14)" do
    test "returns only active, non-deleted sysop emails sorted deterministically" do
      # Two active sysops (visible).
      active_sysop_a = persist_sysop(%{handle: "sysopalpha", email: "alpha@sysop.test"})
      active_sysop_b = persist_sysop(%{handle: "sysopbravo", email: "bravo@sysop.test"})

      # Inactive sysops in each non-active status (must NOT appear).
      _pending_sysop =
        persist_sysop(%{handle: "syspending", email: "pending@sysop.test"})
        |> User.status_changeset(%{status: :pending})
        |> Repo.update!()

      _suspended_sysop =
        persist_sysop(%{handle: "syssuspended", email: "suspended@sysop.test"})
        |> User.status_changeset(%{status: :suspended})
        |> Repo.update!()

      _rejected_sysop =
        persist_sysop(%{handle: "sysrejected", email: "rejected@sysop.test"})
        |> User.status_changeset(%{status: :rejected})
        |> Repo.update!()

      # Deleted sysop (must NOT appear).
      deleted_sysop = persist_sysop(%{handle: "sysdeleted", email: "deleted@sysop.test"})
      {:ok, _} = Accounts.delete_user(deleted_sysop)

      # Active non-sysop user (must NOT appear).
      _active_user =
        AccountsFixtures.user_fixture(%{handle: "regularuser", email: "regular@user.test"})

      # Active mod (must NOT appear).
      _active_mod =
        AccountsFixtures.user_fixture(%{handle: "modonly", email: "mod@only.test"})
        |> User.role_changeset(%{role: :mod})
        |> Repo.update!()

      result = Verification.active_sysop_contact_emails()

      # `active_sysop_contact_emails/0` is a global query over the Repo. Other
      # fixtures in the suite (e.g. invite issuers created by `user_fixture/1`
      # under `invite_only` registration mode) may insert additional sysop
      # users that legitimately satisfy the same predicate. Assert membership
      # of the test-created actives, monotonic sort order, and exclusion of
      # the test-created negatives instead of equality with a closed set.
      assert active_sysop_a.email in result
      assert active_sysop_b.email in result
      assert result == Enum.sort(result)
      refute "pending@sysop.test" in result
      refute "suspended@sysop.test" in result
      refute "rejected@sysop.test" in result
      refute "regular@user.test" in result
      refute "mod@only.test" in result
      # Anonymized email of the deleted user is in deleted-<id>@localhost form.
      refute "deleted@sysop.test" in result
    end

    test "excludes a freshly created non-sysop user" do
      # Replaces the previous `== []` assertion, which assumed a globally
      # empty active-sysop set. `active_sysop_contact_emails/0` is global, so
      # other fixtures in the suite may legitimately produce active sysops;
      # instead, assert that a user we just created with a non-sysop role is
      # absent from the result.
      regular = AccountsFixtures.user_fixture(%{handle: "regular_no_sysop"})
      refute regular.email in Verification.active_sysop_contact_emails()
    end

    defp persist_sysop(attrs) do
      AccountsFixtures.user_fixture(attrs)
      |> User.role_changeset(%{role: :sysop})
      |> Repo.update!()
    end
  end

  describe "consume_reset_token/2 (D-08/D-09/D-10/D-16)" do
    setup do
      Foglet.Accounts.RedemptionThrottle.reset_for_tests()
      :ok
    end

    test "valid raw token updates the password and removes outstanding reset tokens" do
      user = AccountsFixtures.user_fixture(%{password: "original1"})
      {raw_token, _struct} = AccountsFixtures.user_token_fixture(user, "reset_password")
      # Add a second outstanding reset token to prove all are removed.
      {_other_raw, _} = AccountsFixtures.user_token_fixture(user, "reset_password")

      assert {:ok, %User{id: id}} =
               Verification.consume_reset_token(raw_token, %{password: "brandnew1"})

      assert id == user.id

      reloaded = Repo.get!(User, user.id)
      assert Argon2.verify_pass("brandnew1", reloaded.password_hash)
      refute Argon2.verify_pass("original1", reloaded.password_hash)

      refute Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "reset_password"
             )
    end

    test "an already-used raw token cannot be consumed a second time" do
      user = AccountsFixtures.user_fixture(%{password: "original1"})
      {raw_token, _struct} = AccountsFixtures.user_token_fixture(user, "reset_password")

      assert {:ok, _user} =
               Verification.consume_reset_token(raw_token, %{password: "brandnew1"})

      assert {:error, :invalid_or_expired} =
               Verification.consume_reset_token(raw_token, %{password: "anothernew1"})

      reloaded = Repo.get!(User, user.id)
      assert Argon2.verify_pass("brandnew1", reloaded.password_hash)
      refute Argon2.verify_pass("anothernew1", reloaded.password_hash)
    end

    test "an unknown raw token returns invalid_or_expired without changing any password" do
      user = AccountsFixtures.user_fixture(%{password: "original1"})
      # Generate a properly-shaped but unrelated token (never inserted).
      bogus_raw = "Aa0Bb1"

      assert {:error, :invalid_or_expired} =
               Verification.consume_reset_token(bogus_raw, %{password: "brandnew1"})

      reloaded = Repo.get!(User, user.id)
      assert Argon2.verify_pass("original1", reloaded.password_hash)
    end

    test "a malformed raw token returns invalid_or_expired" do
      assert {:error, :invalid_or_expired} =
               Verification.consume_reset_token("not-valid", %{password: "brandnew1"})
    end

    test "an expired raw token returns invalid_or_expired and does not change the password" do
      user = AccountsFixtures.user_fixture(%{password: "original1"})
      {raw_token, struct} = AccountsFixtures.user_token_fixture(user, "reset_password")

      # Backdate inserted_at past the reset_password validity window.
      validity_days = UserToken.validity_days("reset_password")
      backdate = DateTime.utc_now() |> DateTime.add(-(validity_days + 1) * 86_400, :second)

      Repo.update_all(from(t in UserToken, where: t.id == ^struct.id),
        set: [inserted_at: backdate]
      )

      assert {:error, :invalid_or_expired} =
               Verification.consume_reset_token(raw_token, %{password: "brandnew1"})

      reloaded = Repo.get!(User, user.id)
      assert Argon2.verify_pass("original1", reloaded.password_hash)
    end

    test "an invalid password returns a changeset error and does not consume the token" do
      user = AccountsFixtures.user_fixture(%{password: "original1"})
      {raw_token, _struct} = AccountsFixtures.user_token_fixture(user, "reset_password")

      assert {:error, %Ecto.Changeset{}} =
               Verification.consume_reset_token(raw_token, %{password: "short"})

      reloaded = Repo.get!(User, user.id)
      assert Argon2.verify_pass("original1", reloaded.password_hash)

      # Token row must NOT have been deleted on validation failure.
      assert Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "reset_password"
             )
    end

    test "throttles repeated reset-token probes with generic errors and no raw-token audit leak" do
      user = AccountsFixtures.user_fixture(%{password: "original1"})
      {raw_token, _struct} = AccountsFixtures.user_token_fixture(user, "reset_password")

      log =
        capture_log(fn ->
          for _ <- 1..5 do
            assert {:error, %Ecto.Changeset{}} =
                     Verification.consume_reset_token(raw_token, %{password: "short"})
          end

          assert {:error, :invalid_or_expired} =
                   Verification.consume_reset_token(raw_token, %{password: "brandnew1"})
        end)

      refute log =~ raw_token
      assert log =~ "account redemption throttled"

      reloaded = Repo.get!(User, user.id)
      assert Argon2.verify_pass("original1", reloaded.password_hash)

      assert Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "reset_password"
             )
    end

    test "concurrent consumption of the same raw token yields exactly one success" do
      user = AccountsFixtures.user_fixture(%{password: "original1"})
      {raw_token, _struct} = AccountsFixtures.user_token_fixture(user, "reset_password")

      parent = self()

      # Each parallel task must check itself out of the SQL sandbox.
      tasks =
        for i <- 1..2 do
          Task.async(fn ->
            Ecto.Adapters.SQL.Sandbox.allow(FogletBbs.Repo, parent, self())
            Verification.consume_reset_token(raw_token, %{password: "winner#{i}1"})
          end)
        end

      results = Task.await_many(tasks, 5_000)

      successes = Enum.count(results, &match?({:ok, %User{}}, &1))
      failures = Enum.count(results, &match?({:error, :invalid_or_expired}, &1))

      assert successes == 1
      assert failures == 1

      # No reset tokens remain after the winning consume.
      refute Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "reset_password"
             )
    end
  end
end
