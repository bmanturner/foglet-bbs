defmodule Foglet.TUI.Screens.Sysop.ConfigAccountabilityTest do
  use FogletBbs.DataCase, async: false

  alias Foglet.Config
  alias Foglet.Config.Schema
  alias Foglet.TUI.Screens.Sysop.LimitsForm
  alias Foglet.TUI.Screens.Sysop.SiteForm
  alias FogletBbs.AccountsFixtures
  alias FogletBbs.Repo

  @config_keys Map.keys(Schema.defaults())

  setup do
    Config.init_cache()
    for key <- @config_keys, do: Config.invalidate(key)

    for {key, default} <- Schema.defaults() do
      Config.put!(key, default, nil)
    end

    on_exit(fn -> for key <- @config_keys, do: Config.invalidate(key) end)

    %{sysop: sysop_fixture()}
  end

  describe "visibility ledger" do
    test "D-04 accounts for every schema key and no unknown keys" do
      schema_keys = Schema.entries() |> Enum.map(& &1.key) |> MapSet.new()
      ledger_keys = visibility_ledger() |> Enum.map(&elem(&1, 0)) |> MapSet.new()

      assert ledger_keys == schema_keys
    end

    test "D-05 only uses launch accountability status values" do
      allowed =
        MapSet.new([:visible, :conditionally_visible, :intentionally_hidden, :non_pre_alpha])

      statuses =
        visibility_ledger()
        |> Enum.map(fn {_key, {status, _reason}} -> status end)
        |> MapSet.new()

      assert MapSet.subset?(statuses, allowed)
    end

    test "D-04 keeps Sysop form key lists disjoint and equal to schema keys" do
      schema_keys = Schema.entries() |> Enum.map(& &1.key) |> MapSet.new()
      site_keys = SiteForm.site_keys() |> MapSet.new()
      limits_keys = LimitsForm.limits_keys() |> MapSet.new()

      assert MapSet.disjoint?(site_keys, limits_keys)
      assert MapSet.union(site_keys, limits_keys) == schema_keys
    end
  end

  describe "visible control behavior" do
    test "persisted sysop saves representative SITE keys through SiteForm.handle_key/2", %{
      sysop: sysop
    } do
      Config.put!("delivery_mode", "email", nil)
      Config.put!("require_email_verification", false, nil)

      form =
        SiteForm.init(current_user: sysop)
        |> put_draft("registration_mode", "invite_only")
        |> put_draft("invite_code_generators", "any_user")
        |> put_draft("delivery_mode", "email")
        |> put_draft("require_email_verification", true)
        |> put_draft("invite_generation_per_user_limit", 3)

      {form, []} = SiteForm.handle_key(%{key: :char, char: "s", ctrl: true}, form)

      assert form.errors == %{}
      assert Config.get!("registration_mode") == "invite_only"
      assert Config.get!("invite_code_generators") == "any_user"
      assert Config.get!("delivery_mode") == "email"
      assert Config.get!("require_email_verification") == true
      assert Config.get!("invite_generation_per_user_limit") == 3
    end

    test "persisted sysop saves representative LIMITS keys through LimitsForm.handle_key/2", %{
      sysop: sysop
    } do
      form =
        LimitsForm.init(current_user: sysop)
        |> put_draft("max_post_length", 4096)
        |> put_draft("max_thread_title_length", 72)
        |> put_draft("email_verify_resend_cooldown_seconds", 120)

      {form, []} = LimitsForm.handle_key(%{key: :char, char: "s", ctrl: true}, form)

      assert form.errors == %{}
      assert Config.get!("max_post_length") == 4096
      assert Config.get!("max_thread_title_length") == 72
      assert Config.get!("email_verify_resend_cooldown_seconds") == 120
    end

    test "nil actor receives forbidden handling and does not mutate config rows" do
      Config.put!("registration_mode", "open", nil)
      Config.put!("max_post_length", 8192, nil)

      assert Config.put(nil, "registration_mode", "invite_only") == {:error, :forbidden}

      site_form =
        SiteForm.init(current_user: nil)
        |> put_draft("registration_mode", "invite_only")

      assert {_site_form,
              [{:error_modal, "Permission denied. You may have been demoted.", :main_menu}]} =
               SiteForm.handle_key(%{key: :char, char: "s", ctrl: true}, site_form)

      limits_form =
        LimitsForm.init(current_user: nil)
        |> put_draft("max_post_length", 4096)

      assert {_limits_form,
              [{:error_modal, "Permission denied. You may have been demoted.", :main_menu}]} =
               LimitsForm.handle_key(%{key: :char, char: "s", ctrl: true}, limits_form)

      assert Config.get!("registration_mode") == "open"
      assert Config.get!("max_post_length") == 8192
    end

    test "no-email plus required email verification remains blocked before persistence", %{
      sysop: sysop
    } do
      Config.put!("delivery_mode", "email", nil)
      Config.put!("require_email_verification", false, nil)

      form =
        SiteForm.init(current_user: sysop)
        |> put_draft("delivery_mode", "no_email")
        |> put_draft("require_email_verification", true)

      {form, []} = SiteForm.handle_key(%{key: :char, char: "s", ctrl: true}, form)

      assert form.errors["delivery_mode"] == "No-email mode cannot require email verification"

      assert form.errors["require_email_verification"] ==
               "Email verification requires delivery_mode=email"

      assert Config.get!("delivery_mode") == "email"
      assert Config.get!("require_email_verification") == false
    end
  end

  defp visibility_ledger do
    [
      {"registration_mode",
       {:visible,
        "SITE control changes registration policy through Foglet.Config.registration_mode/0 consumers"}},
      {"invite_code_generators",
       {:visible,
        "SITE control changes invite-generation visibility through ShellVisibility and invite actions"}},
      {"delivery_mode",
       {:visible,
        "SITE control changes email/no-email behavior through Foglet.Config.delivery_mode/0 consumers"}},
      {"require_email_verification",
       {:visible,
        "SITE control changes registration/login verification gates through Foglet.Config.require_email_verification?/0 consumers"}},
      {"invite_generation_per_user_limit",
       {:conditionally_visible,
        "Visible only when invite_code_generators == \"any_user\"; affects invite generation cap through Foglet.Config.invite_generation_per_user_limit/0"}},
      {"max_post_length",
       {:visible,
        "LIMITS control affects post body validation through Foglet.Config.max_post_length/0"}},
      {"max_thread_title_length",
       {:visible,
        "LIMITS control affects thread title validation through Foglet.Config.max_thread_title_length/0"}},
      {"email_verify_resend_cooldown_seconds",
       {:visible,
        "LIMITS control affects Verify resend cooldown through Foglet.Config.email_verify_resend_cooldown_seconds/0"}}
    ]
  end

  defp put_draft(form, key, value) do
    %{form | drafts: Map.put(form.drafts, key, value)}
  end

  defp sysop_fixture do
    AccountsFixtures.user_fixture()
    |> Ecto.Changeset.change(%{role: :sysop})
    |> Repo.update!()
  end
end
