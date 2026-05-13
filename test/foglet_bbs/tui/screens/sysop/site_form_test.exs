defmodule Foglet.TUI.Screens.Sysop.SiteFormTest do
  use FogletBbs.DataCase, async: false

  alias Foglet.Config
  alias Foglet.Config.Schema
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Modal
  alias Foglet.TUI.Screens.Sysop.SiteForm
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Modal.Form
  alias FogletBbs.AccountsFixtures
  alias FogletBbs.Repo
  alias Raxol.UI.Layout.Engine

  @config_keys Map.keys(Schema.defaults())

  setup do
    Config.init_cache()
    for key <- @config_keys, do: Config.invalidate(key)

    for {key, default} <- Schema.defaults() do
      Config.put!(key, default, nil)
    end

    on_exit(fn -> for key <- @config_keys, do: Config.invalidate(key) end)
    :ok
  end

  test "site_keys preserves canonical SITE order" do
    assert SiteForm.site_keys() == [
             "registration_mode",
             "invite_code_generators",
             "delivery_mode",
             "require_email_verification",
             "guest_mode_enabled",
             "invite_generation_per_user_limit",
             "ssh_ip_allowlist_enabled"
           ]
  end

  test "SITE read mode renders selectable field rows with friendly values and descriptions" do
    Config.put!("delivery_mode", "email", nil)
    state = SiteForm.init(current_user: sysop_fixture())

    text = render_text(state)

    assert text =~ "▸ Account registrat"
    assert text =~ "Open — anyone can sign up"
    assert text =~ "How new accounts are created."
    assert text =~ "Email delivery"
    assert text =~ "Send email"
    refute text =~ "Save"
    refute text =~ "Cancel"
  end

  test "SITE read mode selection moves deterministically and E/Enter open one-field overlay" do
    state = SiteForm.init(current_user: sysop_fixture())

    {state, []} = SiteForm.handle_key(%{key: :down}, state)
    assert state.focused == 1

    for event <- [%{key: :char, char: "E"}, %{key: :enter}] do
      {updated, [%Effect{type: :modal, payload: {:open, %Modal{} = modal}}]} =
        SiteForm.handle_key(event, state)

      assert updated.focused == 1
      assert %Form{title: "Edit site: Invite code generators", fields: [field]} = modal.message
      assert field.name == :invite_code_generators
    end
  end

  test "SITE read mode Tab and Shift+Tab cycle visible rows and wrap" do
    Config.put!("invite_code_generators", "sysop_only", nil)
    state = SiteForm.init(current_user: sysop_fixture())
    visible_count = length(SiteForm.visible_keys(state))

    {state, []} = SiteForm.handle_key(%{key: :tab}, state)
    assert state.focused == 1

    {state, []} = SiteForm.handle_key(%{key: :shift_tab}, state)
    assert state.focused == 0

    {state, []} = SiteForm.handle_key(%{key: :backtab}, state)
    assert state.focused == visible_count - 1

    Config.put!("invite_code_generators", "any_user", nil)
    state = SiteForm.init(current_user: sysop_fixture())
    visible_count = length(SiteForm.visible_keys(state))

    {state, []} = SiteForm.handle_key(%{key: :tab}, %{state | focused: visible_count - 1})
    assert state.focused == 0
  end

  test "T test email is available only from selected Email delivery field in email mode" do
    Config.put!("delivery_mode", "email", nil)
    state = SiteForm.init(current_user: sysop_fixture())
    delivery_index = Enum.find_index(SiteForm.visible_keys(state), &(&1 == "delivery_mode"))

    {blocked, []} = SiteForm.handle_key(%{key: :char, char: "T"}, state)
    assert blocked.test_email_state == {:error, :no_email_mode}

    {sending, effects} =
      SiteForm.handle_key(%{key: :char, char: "T"}, %{state | focused: delivery_index})

    assert sending.test_email_state == :sending
    assert [%Effect{type: :task, payload: %{op: :sysop_send_test_email}}] = effects
  end

  test "submit_field persists only selected SITE key and refreshes read-mode draft" do
    sysop = sysop_fixture()
    Config.put!("registration_mode", "open", nil)
    Config.put!("invite_code_generators", "sysop_only", nil)

    state = SiteForm.init(current_user: sysop)

    registration_index =
      Enum.find_index(SiteForm.visible_keys(state), &(&1 == "registration_mode"))

    assert {%{drafts: drafts}, [%Effect{type: :modal, payload: :dismiss}]} =
             SiteForm.submit_field(%{state | focused: registration_index}, %{
               registration_mode: "invite_only"
             })

    assert drafts["registration_mode"] == "invite_only"
    assert drafts["invite_code_generators"] == "sysop_only"
    assert Config.get!("registration_mode") == "invite_only"
    assert Config.get!("invite_code_generators") == "sysop_only"
  end

  test "invalid no-email plus required verification stays in overlay and does not persist" do
    sysop = sysop_fixture()
    Config.put!("delivery_mode", "email", nil)
    Config.put!("require_email_verification", true, nil)

    state = SiteForm.init(current_user: sysop)
    delivery_index = Enum.find_index(SiteForm.visible_keys(state), &(&1 == "delivery_mode"))

    assert {state, [%Effect{type: :modal, payload: {:open, %Modal{} = modal}}]} =
             SiteForm.submit_field(%{state | focused: delivery_index}, %{
               delivery_mode: "no_email"
             })

    assert state.submit_state == {:error, "validation"}
    assert state.errors["delivery_mode"] =~ "No-email"
    assert %Form{fields: [%{name: :delivery_mode}], errors: errors} = modal.message
    assert errors.delivery_mode =~ "No-email"
    assert Config.get!("delivery_mode") == "email"
  end

  test "invite limit field is conditionally visible when any user may generate invites" do
    Config.put!("invite_code_generators", "sysop_only", nil)
    state = SiteForm.init(current_user: sysop_fixture())
    refute "invite_generation_per_user_limit" in SiteForm.visible_keys(state)

    Config.put!("invite_code_generators", "any_user", nil)
    state = SiteForm.init(current_user: sysop_fixture())
    assert "invite_generation_per_user_limit" in SiteForm.visible_keys(state)
  end

  defp render_text(state) do
    state
    |> SiteForm.render(Theme.default(), width: 80, height: 12)
    |> Engine.apply_layout(%{width: 80, height: 12})
    |> List.flatten()
    |> Enum.filter(&(&1.type == :text))
    |> Enum.sort_by(&{&1.y, &1.x})
    |> Enum.map_join("\n", & &1.text)
  end

  defp sysop_fixture do
    AccountsFixtures.user_fixture()
    |> Ecto.Changeset.change(%{role: :sysop})
    |> Repo.update!()
  end
end
