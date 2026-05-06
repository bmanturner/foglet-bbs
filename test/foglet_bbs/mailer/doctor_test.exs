defmodule Foglet.Mailer.DoctorTest.FailingMailerAdapter do
  def validate_config(_config), do: :ok
  def deliver(_email, _config), do: {:error, {:smtp_error, "relay refused"}}
end

defmodule Foglet.Mailer.DoctorTest do
  use FogletBbs.DataCase, async: false

  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  alias Foglet.Config
  alias Foglet.Config.Schema
  alias Foglet.Mailer.Doctor

  @config_keys Map.keys(Schema.defaults())

  setup do
    Config.init_cache()

    for key <- @config_keys, do: Config.invalidate(key)

    for {key, default} <- Schema.defaults() do
      Config.put!(key, default, nil)
    end

    original_mailer_config = Application.fetch_env!(:foglet_bbs, Foglet.Mailer)
    original_from = Application.get_env(:foglet_bbs, :mail_from)

    on_exit(fn ->
      Application.put_env(:foglet_bbs, Foglet.Mailer, original_mailer_config)

      if original_from do
        Application.put_env(:foglet_bbs, :mail_from, original_from)
      else
        Application.delete_env(:foglet_bbs, :mail_from)
      end

      for key <- @config_keys, do: Config.invalidate(key)
    end)

    :ok
  end

  test "dry run prints resolved config without sending" do
    Config.put!("delivery_mode", "email", nil)

    output =
      capture_io(fn ->
        assert {:ok, :dry_run} = Doctor.run(start_app: false)
      end)

    assert output =~ "Foglet mailer doctor"
    assert output =~ "delivery_mode: email"
    assert output =~ "adapter: Swoosh.Adapters.Test"
    assert output =~ "smtp: not active"
    assert output =~ "No --to recipient supplied"
  end

  test "default runtime bootstrap supports dry run without caller starting full app" do
    Config.put!("delivery_mode", "email", nil)

    output =
      capture_io(fn ->
        assert {:ok, :dry_run} = Doctor.run()
      end)

    assert output =~ "Foglet mailer doctor"
    assert output =~ "No --to recipient supplied"
  end

  test "delivery_mode no_email skips requested send" do
    Config.put!("delivery_mode", "no_email", nil)

    output =
      capture_io(fn ->
        assert {:error, :delivery_mode_no_email} =
                 Doctor.run(to: "sysop@example.test", start_app: false)
      end)

    assert output =~ "delivery_mode: no_email"
    assert output =~ "Delivery skipped: delivery_mode is no_email."
  end

  test "provider failures print provider reason and log only sanitized class" do
    Config.put!("delivery_mode", "email", nil)

    Application.put_env(:foglet_bbs, Foglet.Mailer,
      adapter: Foglet.Mailer.DoctorTest.FailingMailerAdapter,
      relay: "smtp.example.test",
      port: 587,
      username: "foglet-user",
      password: "secret-password",
      tls: :always,
      auth: :always,
      ssl: false
    )

    output =
      capture_io(fn ->
        log =
          capture_log(fn ->
            assert {:error, {:smtp_error, "relay refused"}} =
                     Doctor.run(to: "sysop@example.test", start_app: false)
          end)

        send(self(), {:log, log})
      end)

    assert_received {:log, log}

    assert output =~ "smtp_relay: \"smtp.example.test\""
    assert output =~ "smtp_username: set"
    assert output =~ "smtp_password: set"
    assert output =~ "Delivery failed."
    assert output =~ "Reason: {:smtp_error, \"relay refused\"}"
    refute output =~ "secret-password"

    assert log =~ "mailer_doctor_delivery_failed"
    assert log =~ "reason_class=smtp_error"
    refute log =~ "sysop@example.test"
    refute log =~ "secret-password"
    refute log =~ "relay refused"
  end
end
