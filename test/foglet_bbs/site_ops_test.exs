defmodule FogletBbs.SiteOpsTest.FailingMailerAdapter do
  def validate_config(_config), do: :ok
  def deliver(_email, _config), do: {:error, :forced_failure}
end

defmodule Foglet.SiteOpsTest do
  use FogletBbs.DataCase, async: false

  alias Foglet.Accounts.User
  alias Foglet.Config
  alias Foglet.SiteOps
  alias FogletBbs.AccountsFixtures
  alias FogletBbs.Repo

  import ExUnit.CaptureLog
  import Swoosh.TestAssertions

  setup :set_swoosh_global

  setup do
    original_delivery_mode = Config.get("delivery_mode", "no_email")

    on_exit(fn ->
      Config.put!("delivery_mode", original_delivery_mode)
      Config.invalidate("delivery_mode")
    end)

    :ok
  end

  defp sysop_fixture(attrs) do
    user = AccountsFixtures.user_fixture(attrs)

    user
    |> User.role_changeset(%{role: :sysop})
    |> Repo.update!()
  end

  describe "send_test_email/1" do
    test "sends a test email to the sysop's own address when delivery_mode is email" do
      Config.put!("delivery_mode", "email")

      sysop =
        sysop_fixture(%{handle: "sysoptest", email: "sysoptest@example.test"})

      assert {:ok, _delivery} = SiteOps.send_test_email(sysop)

      assert_email_sent(fn email ->
        assert email.to == [{"sysoptest", "sysoptest@example.test"}]
        assert email.subject == "Foglet test email"
        body = email.text_body
        assert body =~ "This is a Foglet test email."
        assert body =~ "No action is\nrequired."

        for forbidden <- ["verification code", "reset token", "invite code", "password", "ssh"] do
          assert String.downcase(body) |> String.contains?(forbidden) == false
        end
      end)
    end

    test "non-sysop callers get :forbidden and no email is delivered" do
      Config.put!("delivery_mode", "email")
      user = AccountsFixtures.user_fixture(%{email: "regular@example.test"})

      assert {:error, :forbidden} = SiteOps.send_test_email(user)
      assert_no_email_sent()
    end

    test "guest (nil actor) gets :forbidden and no email is delivered" do
      Config.put!("delivery_mode", "email")

      assert {:error, :forbidden} = SiteOps.send_test_email(nil)
      assert_no_email_sent()
    end

    test "no_email delivery mode returns :no_email_mode without sending" do
      Config.put!("delivery_mode", "no_email")
      sysop = sysop_fixture(%{email: "sysop-no-email@example.test"})

      assert {:error, :no_email_mode} = SiteOps.send_test_email(sysop)
      assert_no_email_sent()
    end

    test "missing sysop email returns :missing_email without sending" do
      Config.put!("delivery_mode", "email")

      # Build a sysop struct with no email — DB schema enforces NOT NULL on
      # `users.email`, so we exercise the in-memory guard with a struct rather
      # than a persisted row. The guard is the trust boundary even if the
      # column is currently NOT NULL, since future flows (or stale caches) may
      # surface a struct with a nil/blank email.
      sysop = %User{
        id: Ecto.UUID.generate(),
        handle: "noemail",
        email: nil,
        role: :sysop,
        status: :active
      }

      assert {:error, :missing_email} = SiteOps.send_test_email(sysop)
      assert_no_email_sent()
    end

    test "blank sysop email returns :missing_email without sending" do
      Config.put!("delivery_mode", "email")

      sysop = %User{
        id: Ecto.UUID.generate(),
        handle: "blankemail",
        email: "",
        role: :sysop,
        status: :active
      }

      assert {:error, :missing_email} = SiteOps.send_test_email(sysop)
      assert_no_email_sent()
    end

    test "mailer failure surfaces as {:error, reason} and is logged with safe context" do
      Config.put!("delivery_mode", "email")

      original_mailer_config = Application.fetch_env!(:foglet_bbs, Foglet.Mailer)

      on_exit(fn ->
        Application.put_env(:foglet_bbs, Foglet.Mailer, original_mailer_config)
      end)

      Application.put_env(:foglet_bbs, Foglet.Mailer,
        adapter: FogletBbs.SiteOpsTest.FailingMailerAdapter
      )

      sysop = sysop_fixture(%{handle: "sysopfail", email: "sysopfail@example.test"})

      log =
        capture_log(fn ->
          assert {:error, :forced_failure} = SiteOps.send_test_email(sysop)
        end)

      assert log =~ "transactional_email_delivery_failed"
      assert log =~ "mail_type=sysop_test_email"
      assert log =~ "delivery_mode=email"
      assert log =~ "recipient_user_id=#{sysop.id}"
      assert log =~ "reason=:forced_failure"
      refute log =~ sysop.email
      refute log =~ sysop.handle
    end
  end
end
