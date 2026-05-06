defmodule FogletBbs.TUI.SysopTestEmailLoggingTest.FailingMailerAdapter do
  def validate_config(_config), do: :ok
  def deliver(_email, _config), do: {:error, :forced_failure}
end

defmodule FogletBbs.TUI.SysopTestEmailLoggingTest.RaisingMailerAdapter do
  def validate_config(_config), do: :ok

  def deliver(email, _config) do
    raise "provider exploded for #{inspect(email.to)} token=raw-secret"
  end
end

defmodule FogletBbs.TUI.SysopTestEmailLoggingTest do
  use FogletBbs.DataCase, async: false

  import ExUnit.CaptureLog

  alias Foglet.Accounts.User
  alias Foglet.Config
  alias Foglet.Config.Schema
  alias Foglet.TUI.App
  alias Foglet.TUI.Screens.Sysop.SiteForm
  alias Foglet.TUI.Theme
  alias FogletBbs.AccountsFixtures
  alias FogletBbs.Repo
  alias Raxol.Core.Runtime.Command
  alias Raxol.UI.Layout.Engine

  @config_keys Map.keys(Schema.defaults())

  setup do
    Config.init_cache()

    for key <- @config_keys, do: Config.invalidate(key)

    for {key, default} <- Schema.defaults() do
      Config.put!(key, default, nil)
    end

    Config.put!("delivery_mode", "email", nil)

    original_mailer_config = Application.fetch_env!(:foglet_bbs, Foglet.Mailer)

    on_exit(fn ->
      Application.put_env(:foglet_bbs, Foglet.Mailer, original_mailer_config)
      for key <- @config_keys, do: Config.invalidate(key)
    end)

    {:ok, sysop: sysop_fixture(%{handle: "sysoptest", email: "sysoptest@example.test"})}
  end

  test "Sysop SITE test-email provider failure logs at the task and UI result boundaries",
       %{
         sysop: sysop
       } do
    Application.put_env(:foglet_bbs, Foglet.Mailer,
      adapter: FogletBbs.TUI.SysopTestEmailLoggingTest.FailingMailerAdapter
    )

    {sending_state, task} = trigger_sysop_test_email(sysop)

    log =
      capture_log(fn ->
        assert {:screen_task_result, :sysop, :sysop_send_test_email,
                {:ok, {:error, :forced_failure}}} =
                 task.()
      end)

    assert log =~ "transactional_email_delivery_failed"
    assert log =~ "mail_type=sysop_test_email"
    assert log =~ "delivery_mode=email"
    assert log =~ "recipient_user_id=#{sysop.id}"
    assert log =~ "reason=:forced_failure"
    refute log =~ "tui_screen_task_failed"
    refute log =~ sysop.email
    refute log =~ sysop.handle

    result_log =
      capture_log(fn ->
        send(
          self(),
          {:after_update,
           App.update(
             {:screen_task_result, :sysop, :sysop_send_test_email,
              {:ok, {:error, :forced_failure}}},
             sending_state
           )}
        )
      end)

    assert_received {:after_update, {after_state, []}}
    assert result_log =~ "sysop_test_email_result_failed"
    assert result_log =~ "screen=sysop"
    assert result_log =~ "operation=sysop_send_test_email"
    assert result_log =~ "delivery_mode=email"
    assert result_log =~ "user_id=#{sysop.id}"
    assert result_log =~ "reason=:forced_failure"
    refute result_log =~ sysop.email
    refute result_log =~ sysop.handle

    assert after_state.screen_state.sysop.site_form.test_email_state == {:error, :forced_failure}

    feedback = render_site_form_text(after_state)
    assert feedback =~ "Test email could not be sent. Check server logs."
    refute feedback =~ "forced_failure"
    refute feedback =~ sysop.email
    refute feedback =~ sysop.handle
  end

  test "Sysop SITE test-email task exception logs privacy-safe task-boundary event and generic state",
       %{
         sysop: sysop
       } do
    Application.put_env(:foglet_bbs, Foglet.Mailer,
      adapter: FogletBbs.TUI.SysopTestEmailLoggingTest.RaisingMailerAdapter
    )

    {sending_state, task} = trigger_sysop_test_email(sysop)

    result =
      capture_log(fn ->
        send(self(), {:task_result, task.()})
      end)

    assert_received {:task_result,
                     {:screen_task_result, :sysop, :sysop_send_test_email,
                      {:error, {:task_failed, :exception}}}}

    assert result =~ "tui_screen_task_failed"
    assert result =~ "screen=sysop"
    assert result =~ "operation=sysop_send_test_email"
    assert result =~ "failure_kind=exception"
    assert result =~ "reason_class=Elixir.RuntimeError"
    assert result =~ "user_id=#{sysop.id}"
    assert result =~ "delivery_mode=email"
    refute result =~ "transactional_email_delivery_failed"
    refute result =~ sysop.email
    refute result =~ sysop.handle
    refute result =~ "raw-secret"

    result_log =
      capture_log(fn ->
        send(
          self(),
          {:after_exception_update,
           App.update(
             {:screen_task_result, :sysop, :sysop_send_test_email,
              {:error, {:task_failed, :exception}}},
             sending_state
           )}
        )
      end)

    assert_received {:after_exception_update, {after_state, []}}
    assert result_log =~ "sysop_test_email_result_failed"
    assert result_log =~ "screen=sysop"
    assert result_log =~ "operation=sysop_send_test_email"
    assert result_log =~ "delivery_mode=email"
    assert result_log =~ "user_id=#{sysop.id}"
    assert result_log =~ "reason={:task_failed, :exception}"
    refute result_log =~ sysop.email
    refute result_log =~ sysop.handle
    refute result_log =~ "raw-secret"

    assert after_state.screen_state.sysop.site_form.test_email_state ==
             {:error, {:task_failed, :exception}}

    state_dump = inspect(after_state.screen_state.sysop.site_form.test_email_state)
    refute state_dump =~ sysop.email
    refute state_dump =~ sysop.handle
    refute state_dump =~ "raw-secret"

    feedback = render_site_form_text(after_state)
    assert feedback =~ "Test email could not be sent. Check server logs."
    refute feedback =~ sysop.email
    refute feedback =~ sysop.handle
    refute feedback =~ "raw-secret"
  end

  defp trigger_sysop_test_email(%User{} = sysop) do
    {:ok, app_state} =
      App.init(%{session_context: %{user: sysop, user_id: sysop.id}})

    {app_state, []} = App.update({:navigate, :sysop}, app_state)
    app_state = focus_delivery_mode(app_state)

    assert {sending_state, [%Command{type: :task, data: task}]} =
             App.update({:key, %{key: :char, char: "T"}}, app_state)

    assert sending_state.screen_state.sysop.site_form.test_email_state == :sending
    {sending_state, task}
  end

  defp focus_delivery_mode(app_state) do
    site_form = app_state.screen_state.sysop.site_form
    delivery_index = Enum.find_index(SiteForm.visible_keys(site_form), &(&1 == "delivery_mode"))
    site_form = %{site_form | focused: delivery_index}
    sysop_state = %{app_state.screen_state.sysop | site_form: site_form}

    %{app_state | screen_state: Map.put(app_state.screen_state, :sysop, sysop_state)}
  end

  defp render_site_form_text(app_state) do
    site_form = app_state.screen_state.sysop.site_form

    site_form
    |> SiteForm.render(Theme.default(), width: 100, height: 12)
    |> Engine.apply_layout(%{width: 100, height: 12})
    |> List.flatten()
    |> Enum.filter(&(&1.type == :text))
    |> Enum.sort_by(&{&1.y, &1.x})
    |> Enum.map_join("\n", & &1.text)
  end

  defp sysop_fixture(attrs) do
    attrs
    |> AccountsFixtures.user_fixture()
    |> Ecto.Changeset.change(%{role: :sysop})
    |> Repo.update!()
  end
end
