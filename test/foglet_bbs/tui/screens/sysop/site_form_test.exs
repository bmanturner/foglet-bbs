defmodule Foglet.TUI.Screens.Sysop.SiteFormTest do
  use FogletBbs.DataCase, async: false

  import Foglet.TUI.RenderHelpers

  alias Foglet.Config
  alias Foglet.Config.Schema
  alias Foglet.TUI.Screens.Sysop.SiteForm
  alias Foglet.TUI.Theme
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

    :ok
  end

  describe "delivery mode placement" do
    test "site_keys places delivery_mode before require_email_verification" do
      assert SiteForm.site_keys() == [
               "registration_mode",
               "invite_code_generators",
               "delivery_mode",
               "require_email_verification",
               "invite_generation_per_user_limit"
             ]
    end

    test "init loads delivery_mode draft from Config" do
      Config.put!("delivery_mode", "email", nil)

      form = SiteForm.init([])

      assert form.drafts["delivery_mode"] == "email"
    end

    test "render shows delivery_mode description and current value" do
      Config.put!("delivery_mode", "email", nil)

      text =
        SiteForm.init([])
        |> SiteForm.render(Theme.default())
        |> collect_text_values()
        |> Enum.join("\n")

      assert text =~ "delivery_mode: email"
      assert text =~ "Outbound transactional delivery mode"
    end

    test "enum first-character input selects email and no_email" do
      form = SiteForm.init([])
      delivery_index = Enum.find_index(SiteForm.visible_keys(form), &(&1 == "delivery_mode"))
      form = %{form | focused: delivery_index}

      {form, []} = SiteForm.handle_key(%{key: :char, char: "e"}, form)
      assert form.drafts["delivery_mode"] == "email"

      {form, []} = SiteForm.handle_key(%{key: :char, char: "n"}, form)
      assert form.drafts["delivery_mode"] == "no_email"
    end
  end

  describe "submit delivery mode validation" do
    test "blocks no_email when email verification is required without persisting drafts" do
      sysop = sysop_fixture()
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

    test "allows valid delivery and verification combinations" do
      sysop = sysop_fixture()

      for {delivery_mode, require_verification} <- [
            {"email", true},
            {"email", false},
            {"no_email", false}
          ] do
        Config.put!("delivery_mode", "email", nil)
        Config.put!("require_email_verification", true, nil)

        form =
          SiteForm.init(current_user: sysop)
          |> put_draft("delivery_mode", delivery_mode)
          |> put_draft("require_email_verification", require_verification)

        {form, []} = SiteForm.handle_key(%{key: :char, char: "s", ctrl: true}, form)

        refute Map.has_key?(form.errors, "delivery_mode")
        refute Map.has_key?(form.errors, "require_email_verification")
        assert Config.get!("delivery_mode") == delivery_mode
        assert Config.get!("require_email_verification") == require_verification
      end
    end
  end

  # =========================================================================
  # visible_keys re-init (Pitfall 6) — Phase 25 Plan 04
  # =========================================================================

  describe "visible_keys re-init (Pitfall 6)" do
    test "invite_generation_per_user_limit present when invite_code_generators == any_user" do
      Config.put!("invite_code_generators", "any_user", nil)
      form = SiteForm.init([])
      assert "invite_generation_per_user_limit" in SiteForm.visible_keys(form)
    end

    test "invite_generation_per_user_limit absent when invite_code_generators != any_user" do
      Config.put!("invite_code_generators", "sysop_only", nil)
      form = SiteForm.init([])
      refute "invite_generation_per_user_limit" in SiteForm.visible_keys(form)
    end

    test "mutating invite_code_generators draft to any_user makes limit field visible" do
      Config.put!("invite_code_generators", "sysop_only", nil)
      form = SiteForm.init([])
      refute "invite_generation_per_user_limit" in SiteForm.visible_keys(form)

      form = put_draft(form, "invite_code_generators", "any_user")
      assert "invite_generation_per_user_limit" in SiteForm.visible_keys(form)
    end

    test "mutating invite_code_generators draft away from any_user hides limit field" do
      Config.put!("invite_code_generators", "any_user", nil)
      form = SiteForm.init([])
      assert "invite_generation_per_user_limit" in SiteForm.visible_keys(form)

      form = put_draft(form, "invite_code_generators", "sysop_only")
      refute "invite_generation_per_user_limit" in SiteForm.visible_keys(form)
    end

    test "render with any_user renders invite_generation_per_user_limit in Modal.Form output" do
      Config.put!("invite_code_generators", "any_user", nil)
      form = SiteForm.init([])

      rendered_text =
        form
        |> SiteForm.render(Theme.default())
        |> collect_text_values()
        |> Enum.join("\n")

      assert String.contains?(rendered_text, "invite_generation_per_user_limit"),
             "Expected invite_generation_per_user_limit in rendered output when any_user"
    end

    test "render without any_user hides invite_generation_per_user_limit" do
      Config.put!("invite_code_generators", "sysop_only", nil)
      form = SiteForm.init([])

      rendered_text =
        form
        |> SiteForm.render(Theme.default())
        |> collect_text_values()
        |> Enum.join("\n")

      refute String.contains?(rendered_text, "invite_generation_per_user_limit"),
             "Expected invite_generation_per_user_limit absent when generators != any_user"
    end
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
