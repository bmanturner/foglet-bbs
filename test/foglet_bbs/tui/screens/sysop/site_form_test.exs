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

  # =========================================================================
  # Phase 28 Plan 04 Task 1 — SiteForm.State sibling (D-17, D-21)
  # =========================================================================

  describe "SiteForm.State sibling" do
    alias Foglet.TUI.Screens.Sysop.SiteForm.State, as: SState
    alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

    test "new/1 seeds drafts from Foglet.Config.get!/1 with errors empty + focused 0" do
      Config.put!("delivery_mode", "email", nil)
      Config.put!("registration_mode", "open", nil)

      state = SState.new([])

      assert state.drafts["delivery_mode"] == "email"
      assert state.drafts["registration_mode"] == "open"
      assert state.errors == %{}
      assert state.focused == 0
      assert state.current_user == nil
    end

    test "new/1 stores current_user when provided" do
      sysop = sysop_fixture()
      state = SState.new(current_user: sysop)
      assert state.current_user == sysop
    end

    test "visible_keys/1 returns 4 keys when invite_code_generators != any_user" do
      Config.put!("invite_code_generators", "sysop_only", nil)
      state = SState.new([])
      visible = SState.visible_keys(state)

      refute "invite_generation_per_user_limit" in visible
      assert length(visible) == 4
    end

    test "visible_keys/1 returns 5 keys when invite_code_generators == any_user" do
      Config.put!("invite_code_generators", "any_user", nil)
      state = SState.new([])
      visible = SState.visible_keys(state)

      assert "invite_generation_per_user_limit" in visible
      assert length(visible) == 5
    end

    test "build_modal_form/1 returns Modal.Form with fields matching visible_keys" do
      Config.put!("invite_code_generators", "sysop_only", nil)
      state = SState.new([])
      form = SState.build_modal_form(state)

      assert %ModalForm{} = form
      assert length(form.fields) == length(SState.visible_keys(state))
      assert length(form.fields) == 4
    end

    test "build_modal_form/1 maps Schema types to ModalForm field types" do
      Config.put!("invite_code_generators", "any_user", nil)
      state = SState.new([])
      form = SState.build_modal_form(state)

      types_by_label = Map.new(form.fields, fn f -> {f.label, f.type} end)

      # registration_mode: :string + enum -> :enum
      assert types_by_label["registration_mode"] == :enum
      # invite_code_generators: :string + enum -> :enum
      assert types_by_label["invite_code_generators"] == :enum
      # delivery_mode: :string + enum -> :enum
      assert types_by_label["delivery_mode"] == :enum
      # require_email_verification: :boolean -> :boolean
      assert types_by_label["require_email_verification"] == :boolean
      # invite_generation_per_user_limit: :integer -> :integer
      assert types_by_label["invite_generation_per_user_limit"] == :integer
    end

    test "build_modal_form/1 enum value is preserved in field spec :value" do
      Config.put!("delivery_mode", "email", nil)
      state = SState.new([])
      form = SState.build_modal_form(state)

      delivery_field = Enum.find(form.fields, fn f -> f.label == "delivery_mode" end)
      assert delivery_field.value == "email"
      assert delivery_field.type == :enum
      assert "email" in delivery_field.choices
      assert "no_email" in delivery_field.choices
    end

    test "validate_delivery_verification_pair/1 errors on no_email + require_verification true" do
      payload = %{delivery_mode: "no_email", require_email_verification: true}

      assert {:error, errors} = SState.validate_delivery_verification_pair(payload)
      assert errors[:delivery_mode] =~ "No-email"
      assert errors[:require_email_verification] =~ "Email verification"
    end

    test "validate_delivery_verification_pair/1 returns :ok for valid combinations" do
      assert :ok =
               SState.validate_delivery_verification_pair(%{
                 delivery_mode: "email",
                 require_email_verification: true
               })

      assert :ok =
               SState.validate_delivery_verification_pair(%{
                 delivery_mode: "email",
                 require_email_verification: false
               })

      assert :ok =
               SState.validate_delivery_verification_pair(%{
                 delivery_mode: "no_email",
                 require_email_verification: false
               })
    end

    test "reseed_drafts/1 reloads drafts from Foglet.Config.get!/1 and resets errors + focus" do
      Config.put!("delivery_mode", "email", nil)
      state = SState.new([])

      mutated = %{
        state
        | drafts: Map.put(state.drafts, "delivery_mode", "no_email"),
          errors: %{"delivery_mode" => "stale"},
          focused: 3
      }

      reseeded = SState.reseed_drafts(mutated)

      assert reseeded.drafts["delivery_mode"] == "email"
      assert reseeded.errors == %{}
      assert reseeded.focused == 0
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
