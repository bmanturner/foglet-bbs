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
               "guest_mode_enabled",
               "invite_generation_per_user_limit"
             ]
    end

    test "init loads delivery_mode draft from Config" do
      Config.put!("delivery_mode", "email", nil)

      form = SiteForm.init([])

      assert form.drafts["delivery_mode"] == "email"
    end

    test "init keeps delivery_mode in visible keys with current value" do
      Config.put!("delivery_mode", "email", nil)

      form = SiteForm.init([])

      assert "delivery_mode" in SiteForm.visible_keys(form)
      assert form.drafts["delivery_mode"] == "email"
    end

    test "enum cycles via :down events (Modal.Form contract)" do
      # Phase 28 Plan 04 behavior change: enum selection moved from first-char
      # jump (legacy bespoke) to up/down cycling (Modal.Form contract). See
      # Phase 28 Plan 04 SUMMARY for rationale.
      Config.put!("delivery_mode", "email", nil)

      form = SiteForm.init([])
      delivery_index = Enum.find_index(SiteForm.visible_keys(form), &(&1 == "delivery_mode"))
      form = %{form | focused: delivery_index}

      {form, []} = SiteForm.handle_key(%{key: :down}, form)
      assert form.drafts["delivery_mode"] == "no_email"

      {form, []} = SiteForm.handle_key(%{key: :up}, form)
      assert form.drafts["delivery_mode"] == "email"
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

    test "visible_keys/1 returns 5 keys when invite_code_generators != any_user" do
      Config.put!("invite_code_generators", "sysop_only", nil)
      state = SState.new([])
      visible = SState.visible_keys(state)

      refute "invite_generation_per_user_limit" in visible
      assert "guest_mode_enabled" in visible
      assert length(visible) == 5
    end

    test "visible_keys/1 returns 6 keys when invite_code_generators == any_user" do
      Config.put!("invite_code_generators", "any_user", nil)
      state = SState.new([])
      visible = SState.visible_keys(state)

      assert "invite_generation_per_user_limit" in visible
      assert "guest_mode_enabled" in visible
      assert length(visible) == 6
    end

    test "build_modal_form/1 returns Modal.Form with fields matching visible_keys" do
      Config.put!("invite_code_generators", "sysop_only", nil)
      state = SState.new([])
      form = SState.build_modal_form(state)

      assert %ModalForm{} = form
      assert length(form.fields) == length(SState.visible_keys(state))
      assert length(form.fields) == 5
    end

    test "build_modal_form/1 maps Schema types to ModalForm field types" do
      Config.put!("invite_code_generators", "any_user", nil)
      state = SState.new([])
      form = SState.build_modal_form(state)

      # FOG-344: enum SITE keys carry operator-facing field labels distinct
      # from the schema key. Index by :name (atom) which remains stable.
      types_by_name = Map.new(form.fields, fn f -> {f.name, f.type} end)

      assert types_by_name[:registration_mode] == :enum
      assert types_by_name[:invite_code_generators] == :enum
      assert types_by_name[:delivery_mode] == :enum
      assert types_by_name[:require_email_verification] == :boolean
      assert types_by_name[:guest_mode_enabled] == :boolean
      assert types_by_name[:invite_generation_per_user_limit] == :integer
    end

    test "build_modal_form/1 enum value is preserved in field spec :value" do
      Config.put!("delivery_mode", "email", nil)
      state = SState.new([])
      form = SState.build_modal_form(state)

      delivery_field = Enum.find(form.fields, fn f -> f.name == :delivery_mode end)
      assert delivery_field.value == "email"
      assert delivery_field.type == :enum
      # FOG-344: choices are now {label, value} pairs; raw values still present.
      values = Enum.map(delivery_field.choices, fn {_label, value} -> value end)
      assert "email" in values
      assert "no_email" in values
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

  # =========================================================================
  # Phase 28 Plan 04 Task 2 — Modal.Form-backed wrapper (D-17, D-19, D-20, FORM-04, FORM-06)
  # =========================================================================

  describe "SiteForm Modal.Form wrapper (Phase 28 Plan 04 Task 2)" do
    test "render delegates to Modal.Form with no legacy ▸ marker" do
      Config.put!("delivery_mode", "email", nil)

      text =
        SiteForm.init([])
        |> SiteForm.render(Theme.default())
        |> collect_text_values()
        |> Enum.join("\n")

      refute text =~ "▸"
    end

    test "FORM-04 routing: char input lands in the focused integer field's draft" do
      sysop = sysop_fixture()
      Config.put!("invite_code_generators", "any_user", nil)
      Config.put!("invite_generation_per_user_limit", 0, nil)

      form = SiteForm.init(current_user: sysop)
      visible = SiteForm.visible_keys(form)
      limit_index = Enum.find_index(visible, &(&1 == "invite_generation_per_user_limit"))
      assert is_integer(limit_index)

      # Clear the draft first so TextInput doesn't append to the seeded "0".
      form = %{
        form
        | focused: limit_index,
          drafts: Map.put(form.drafts, "invite_generation_per_user_limit", nil)
      }

      {form, []} = SiteForm.handle_key(%{key: :char, char: "5"}, form)

      # Modal.Form's :integer field is backed by TextInput; the typed value
      # flows back through the wrapper's drafts map (FORM-04 routing).
      assert form.drafts["invite_generation_per_user_limit"] == 5
    end

    test "Ctrl+S invokes Foglet.Config.put/3 from current focus without moving focus (D-19)" do
      sysop = sysop_fixture()
      Config.put!("delivery_mode", "email", nil)
      Config.put!("registration_mode", "open", nil)

      form =
        SiteForm.init(current_user: sysop)
        |> put_draft("registration_mode", "invite_only")

      assert form.focused == 0

      {form, _events} = SiteForm.handle_key(%{key: :char, char: "s", ctrl: true}, form)

      assert form.focused == 0
      assert Config.get!("registration_mode") == "invite_only"
    end

    test "Enter invokes Foglet.Config.put/3 from current non-last focus (D-19)" do
      sysop = sysop_fixture()
      Config.put!("invite_code_generators", "sysop_only", nil)
      Config.put!("registration_mode", "open", nil)

      form =
        SiteForm.init(current_user: sysop)
        |> put_draft("registration_mode", "sysop_approved")

      assert form.focused == 0

      {form, _events} = SiteForm.handle_key(%{key: :enter}, form)

      assert form.focused == 0
      assert Config.get!("registration_mode") == "sysop_approved"
    end

    test "Enter on last visible field invokes Foglet.Config.put/3 (D-19)" do
      sysop = sysop_fixture()
      Config.put!("invite_code_generators", "sysop_only", nil)
      Config.put!("registration_mode", "open", nil)

      form =
        SiteForm.init(current_user: sysop)
        |> put_draft("registration_mode", "sysop_approved")

      visible = SiteForm.visible_keys(form)
      last_idx = length(visible) - 1
      form = %{form | focused: last_idx}

      {_form, _events} = SiteForm.handle_key(%{key: :enter}, form)

      assert Config.get!("registration_mode") == "sysop_approved"
    end

    test "D-20 validation rejects no_email + require_email_verification true; no Config.put" do
      sysop = sysop_fixture()
      Config.put!("delivery_mode", "email", nil)
      Config.put!("require_email_verification", false, nil)

      form =
        SiteForm.init(current_user: sysop)
        |> put_draft("delivery_mode", "no_email")
        |> put_draft("require_email_verification", true)

      {form, []} = SiteForm.handle_key(%{key: :char, char: "s", ctrl: true}, form)

      # Errors flow through SiteForm's string-keyed errors map (preserved API)
      # and via Modal.Form.set_errors/2 inside the per-render form.
      assert form.errors["delivery_mode"] =~ "No-email"
      assert form.errors["require_email_verification"] =~ "Email verification"

      # Config row was NOT updated.
      assert Config.get!("delivery_mode") == "email"
      assert Config.get!("require_email_verification") == false
    end

    test "D-21 conditional visibility: hiding the limit field removes it from render" do
      Config.put!("invite_code_generators", "any_user", nil)
      Config.put!("invite_generation_per_user_limit", 0, nil)

      form = SiteForm.init([])
      assert "invite_generation_per_user_limit" in SiteForm.visible_keys(form)

      form = put_draft(form, "invite_code_generators", "sysop_only")

      text =
        form
        |> SiteForm.render(Theme.default())
        |> collect_text_values()
        |> Enum.join("\n")

      refute String.contains?(text, "invite_generation_per_user_limit"),
             "Expected limit field absent from render after switching away from any_user"
    end

    test "FORM-06 Esc reseeds drafts from Foglet.Config.get!/1 with no inline status copy" do
      Config.put!("delivery_mode", "email", nil)

      form =
        SiteForm.init([])
        |> put_draft("delivery_mode", "no_email")

      {form, []} = SiteForm.handle_key(%{key: :escape}, form)

      assert form.drafts["delivery_mode"] == "email"

      text =
        form
        |> SiteForm.render(Theme.default())
        |> collect_text_values()
        |> Enum.join("\n")

      # D-12: no inline "discarded" status copy on Esc.
      refute text =~ "discarded"
      refute text =~ "Discarded"
    end
  end

  # =========================================================================
  # Phase 28 Plan 06 — BL-02: FORM-05 lock + status row persistence on SiteForm
  # =========================================================================
  #
  # These tests assert that SiteForm preserves Modal.Form's `submit_state`
  # across the per-render rebuild driven by `SState.build_modal_form/1`. Today
  # `sync_back/2` discards the form's submit_state, so:
  #   * the FORM-05 lock guard has zero effect on this consumer (a held /
  #     double Ctrl+S calls Foglet.Config.put/3 multiple times, vs the
  #     "exactly once" contract documented at form.ex D-02), and
  #   * the D-08/D-09 status row ("Saved." / "Error: validation") never
  #     reaches the operator on the Sysop SITE form.
  #
  # See .planning/phases/28-modal-form-substrate/28-VERIFICATION.md (BL-02)
  # and .planning/phases/28-modal-form-substrate/28-REVIEW.md (BL-02 §Fix).
  describe "BL-02: FORM-05 lock + status row persistence on SiteForm" do
    test "double Ctrl+S preserves submit_state across the per-render rebuild" do
      sysop = sysop_fixture()
      Config.put!("delivery_mode", "email", nil)
      Config.put!("registration_mode", "open", nil)
      Config.put!("require_email_verification", false, nil)

      form =
        SiteForm.init(current_user: sysop)
        |> put_draft("registration_mode", "invite_only")

      # First Ctrl+S: synchronous Config.put cascade; form should land in :saved.
      {form1, []} = SiteForm.handle_key(%{key: :char, char: "s", ctrl: true}, form)

      assert form1.submit_state == :saved,
             "Expected SiteForm.State.submit_state == :saved after a successful " <>
               "Ctrl+S, got #{inspect(form1.submit_state)}. The Modal.Form's " <>
               "submit_state must survive sync_back/2 (BL-02)."

      # Mutate the persisted Config row externally to detect a re-fire of the
      # Config.put cascade on the second Ctrl+S. If the lock + persisted
      # submit_state is doing its job, the second Ctrl+S triggers the auto-reset
      # then the form is built fresh from the (mutated) Config draft seed... but
      # critically, after sync_back, the resulting submit_state must remain a
      # terminal state, not silently reset to :idle.
      {form2, []} = SiteForm.handle_key(%{key: :char, char: "s", ctrl: true}, form1)

      # The second Ctrl+S goes through auto-reset (:saved -> :idle) then submits
      # again with the still-:invite_only draft, landing back in :saved. The
      # persistence assertion is identical: terminal submit_state must survive.
      assert form2.submit_state == :saved,
             "Expected SiteForm.State.submit_state == :saved after a second " <>
               "Ctrl+S, got #{inspect(form2.submit_state)}. submit_state must " <>
               "be persisted onto SState by sync_back/2 (BL-02)."
    end

    test "successful Ctrl+S renders \"Saved.\" status row (D-08/D-09)" do
      sysop = sysop_fixture()
      Config.put!("delivery_mode", "email", nil)
      Config.put!("registration_mode", "open", nil)
      Config.put!("require_email_verification", false, nil)

      form =
        SiteForm.init(current_user: sysop)
        |> put_draft("registration_mode", "invite_only")

      {form, []} = SiteForm.handle_key(%{key: :char, char: "s", ctrl: true}, form)

      text =
        form
        |> SiteForm.render(Theme.default())
        |> collect_text_values()
        |> Enum.join("\n")

      assert text =~ "Saved.",
             "Expected the rendered Modal.Form output to contain \"Saved.\" " <>
               "after a successful Ctrl+S cascade. The D-08/D-09 status row " <>
               "is silently dropped today because submit_state is not persisted " <>
               "across the per-render rebuild (BL-02)."
    end

    test "validation-failure Ctrl+S renders \"Error: validation\" status row" do
      sysop = sysop_fixture()
      Config.put!("delivery_mode", "email", nil)
      Config.put!("require_email_verification", false, nil)

      form =
        SiteForm.init(current_user: sysop)
        |> put_draft("delivery_mode", "no_email")
        |> put_draft("require_email_verification", true)

      {form, []} = SiteForm.handle_key(%{key: :char, char: "s", ctrl: true}, form)

      text =
        form
        |> SiteForm.render(Theme.default())
        |> collect_text_values()
        |> Enum.join("\n")

      assert text =~ "Error: validation",
             "Expected the rendered Modal.Form output to contain " <>
               "\"Error: validation\" after a validate_delivery_verification_pair " <>
               "rejection. submit_state {:error, \"validation\"} is dropped today " <>
               "by sync_back/2 (BL-02)."
    end

    test "auto-reset still collapses :saved to :idle on the next non-locked event" do
      # Regression guard for the auto-reset preamble (form.ex:178-184). After
      # the BL-02 fix, sync_back persists the post-event submit_state — which
      # the preamble has already collapsed to :idle on a non-locked event. So
      # a Tab after a successful save must NOT leave "Saved." pinned forever.
      sysop = sysop_fixture()
      Config.put!("delivery_mode", "email", nil)
      Config.put!("registration_mode", "open", nil)
      Config.put!("require_email_verification", false, nil)

      form =
        SiteForm.init(current_user: sysop)
        |> put_draft("registration_mode", "invite_only")

      {form, []} = SiteForm.handle_key(%{key: :char, char: "s", ctrl: true}, form)
      assert form.submit_state == :saved

      {form, []} = SiteForm.handle_key(%{key: :tab}, form)

      assert form.submit_state == :idle,
             "Expected auto-reset preamble to collapse :saved -> :idle on the " <>
               "next non-locked event. Got #{inspect(form.submit_state)}."

      text =
        form
        |> SiteForm.render(Theme.default())
        |> collect_text_values()
        |> Enum.join("\n")

      refute text =~ "Saved.",
             "Expected \"Saved.\" to disappear after auto-reset on Tab; the " <>
               "form is editable again per D-04."
    end
  end

  # =========================================================================
  # Phase 29 Plan 03 — D-18 / D-19 Enter persistence and "Saved." status row
  # =========================================================================
  #
  # The Phase 28 substrate (validate_delivery_verification_pair pre-flight,
  # Foglet.Config.put/3 cascade, Modal.Form.set_submit_state(:saved) on
  # all-keys-success) already delivers everything D-18 and D-19 require. The
  # describe block below locks the contract as a Phase 29 invariant — if a
  # future refactor breaks the Enter→put→Saved. flow, these tests fail with
  # named acceptance copy.

  describe "Sysop Site Enter persistence (D-18, D-19)" do
    test "Enter on the last visible field persists every draft via Foglet.Config.put/3" do
      sysop = sysop_fixture()
      Config.put!("registration_mode", "open", nil)
      Config.put!("invite_code_generators", "sysop_only", nil)

      form =
        SiteForm.init(current_user: sysop)
        |> put_draft("registration_mode", "invite_only")

      visible = SiteForm.visible_keys(form)
      last_idx = length(visible) - 1
      form = %{form | focused: last_idx}

      {form_after_enter, []} = SiteForm.handle_key(%{key: :enter}, form)

      # D-18: persisted via Foglet.Config.put/3
      assert Config.get!("registration_mode") == "invite_only"

      # D-19: next render contains the Phase 28 D-08 "Saved." substring.
      text =
        form_after_enter
        |> SiteForm.render(Theme.default())
        |> collect_text_values()
        |> Enum.join("\n")

      assert text =~ "Saved.",
             "Expected the Phase 28 D-08 \"Saved.\" status row after a " <>
               "successful Enter cascade. Got: #{inspect(text)}"
    end

    test "Validation failure does NOT persist and does NOT show Saved." do
      sysop = sysop_fixture()
      Config.put!("delivery_mode", "email", nil)
      Config.put!("require_email_verification", false, nil)

      # Force validate_delivery_verification_pair/1 to reject:
      # delivery_mode == "no_email" AND require_email_verification == true.
      form =
        SiteForm.init(current_user: sysop)
        |> put_draft("delivery_mode", "no_email")
        |> put_draft("require_email_verification", true)

      visible = SiteForm.visible_keys(form)
      last_idx = length(visible) - 1
      form = %{form | focused: last_idx}

      {form_after_enter, []} = SiteForm.handle_key(%{key: :enter}, form)

      # D-18 failure path: no Config row updated.
      assert Config.get!("delivery_mode") == "email"
      assert Config.get!("require_email_verification") == false

      # submit_state is in the {:error, _} terminal — verified directly and
      # also via the rendered text (no "Saved.").
      assert match?({:error, _}, form_after_enter.submit_state),
             "Expected submit_state == {:error, _} after validation rejection, " <>
               "got #{inspect(form_after_enter.submit_state)}"

      text =
        form_after_enter
        |> SiteForm.render(Theme.default())
        |> collect_text_values()
        |> Enum.join("\n")

      refute text =~ "Saved.",
             "Expected NO \"Saved.\" status row after a validation rejection. " <>
               "Got: #{inspect(text)}"
    end
  end

  # =========================================================================
  # Phase 29 Plan 03 — D-20 / D-21 Esc reseed (Phase 28 D-12 honored)
  # =========================================================================
  #
  # SPEC SYSOP-03's "discard status row" acceptance is amended by D-20/D-21:
  # the visible signal of Esc is field-value reversion on the next render.
  # SiteForm gains no `status_message` field. No "draft discarded" / "Changes
  # discarded" / "Discarded" copy may appear. Esc must not navigate.

  describe "Sysop Site Esc reseed (D-20, D-21)" do
    test "(a) After Esc, drafts equal saved Foglet.Config values" do
      Config.put!("registration_mode", "open", nil)

      form =
        SiteForm.init([])
        |> put_draft("registration_mode", "invite_only")

      # Pre-condition: draft was mutated away from saved.
      assert form.drafts["registration_mode"] == "invite_only"
      assert Config.get!("registration_mode") == "open"

      {form_after_esc, []} = SiteForm.handle_key(%{key: :escape}, form)

      # D-20/D-21 (a): drafts reseeded to saved Config values.
      assert form_after_esc.drafts["registration_mode"] ==
               Config.get!("registration_mode")
    end

    test "(b) After Esc, rendered field values reflect saved Foglet.Config" do
      Config.put!("registration_mode", "open", nil)

      form =
        SiteForm.init([])
        |> put_draft("registration_mode", "invite_only")

      {form_after_esc, []} = SiteForm.handle_key(%{key: :escape}, form)

      text =
        form_after_esc
        |> SiteForm.render(Theme.default())
        |> collect_text_values()
        |> Enum.join("\n")

      # D-20/D-21 (b): drafts reseeded to saved Config value; the rendered
      # selection (per FOG-344, shown via the operator-facing label) marks the
      # saved value, and the previously-mutated draft is NOT the selection.
      assert form_after_esc.drafts["registration_mode"] == "open"

      assert text =~ ~r/●\s*Open — anyone can sign up/,
             "Expected the saved 'open' value's label to be the selected radio after " <>
               "Esc reseed. Got: #{inspect(text)}"

      assert text =~ ~r/◇\s*Invite only — requires an invite code/,
             "Expected the previously-mutated 'invite_only' draft to be unselected " <>
               "after Esc reseed. Got: #{inspect(text)}"
    end

    test "(c) Esc does not navigate away from the Sysop Site tab" do
      Config.put!("registration_mode", "open", nil)

      form =
        SiteForm.init([])
        |> put_draft("registration_mode", "invite_only")

      {_form_after_esc, events} = SiteForm.handle_key(%{key: :escape}, form)

      # D-20/D-21 (c): no navigate event in the events list.
      refute Enum.any?(events, fn
               {:navigate, _} -> true
               :pop_screen -> true
               _ -> false
             end),
             "Expected NO navigate/pop event after Esc on Sysop Site. " <>
               "Got events: #{inspect(events)}"
    end

    test "After Esc, no inline 'discarded' status row appears (Phase 28 D-12)" do
      Config.put!("registration_mode", "open", nil)

      form =
        SiteForm.init([])
        |> put_draft("registration_mode", "invite_only")

      {form_after_esc, []} = SiteForm.handle_key(%{key: :escape}, form)

      text =
        form_after_esc
        |> SiteForm.render(Theme.default())
        |> collect_text_values()
        |> Enum.join("\n")

      # D-20: Phase 28 D-12 honored — no inline discard status copy.
      for forbidden <- ["draft discarded", "Changes discarded", "Discarded"] do
        refute text =~ forbidden,
               "Found forbidden discard substring #{inspect(forbidden)} in: " <>
                 inspect(text)
      end
    end
  end

  # =========================================================================
  # FOG-344 — operator-facing labels for enum SITE keys with raw-value persistence
  # =========================================================================

  describe "FOG-344 enum operator-facing labels" do
    test "registration_mode renders human label, not raw atom" do
      Config.put!("registration_mode", "open", nil)
      form = SiteForm.init([])

      text =
        form
        |> SiteForm.render(Theme.default())
        |> collect_text_values()
        |> Enum.join("\n")

      assert String.contains?(text, "Open — anyone can sign up")
      assert String.contains?(text, "Invite only — requires an invite code")
      assert String.contains?(text, "Sysop approval — applications queue for review")
      assert String.contains?(text, "Account registration")
    end

    test "delivery_mode renders human labels for both choices" do
      Config.put!("delivery_mode", "email", nil)
      form = SiteForm.init([])

      text =
        form
        |> SiteForm.render(Theme.default())
        |> collect_text_values()
        |> Enum.join("\n")

      assert String.contains?(text, "Send email")
      assert String.contains?(text, "No email (offline mode)")
      assert String.contains?(text, "Email delivery")
    end

    test "invite_code_generators renders human labels for all three choices" do
      Config.put!("invite_code_generators", "sysop_only", nil)
      form = SiteForm.init([])

      text =
        form
        |> SiteForm.render(Theme.default())
        |> collect_text_values()
        |> Enum.join("\n")

      assert String.contains?(text, "Sysops only")
      assert String.contains?(text, "Sysops and moderators")
      assert String.contains?(text, "Any signed-in user")
      assert String.contains?(text, "Invite code generators")
    end

    test "selecting a labeled enum round-trips a raw value through Foglet.Config.put/3" do
      sysop = sysop_fixture()
      Config.put!("registration_mode", "open", nil)

      form = SiteForm.init(current_user: sysop)

      reg_index =
        SiteForm.visible_keys(form)
        |> Enum.find_index(&(&1 == "registration_mode"))

      form = %{form | focused: reg_index}

      # Cycle Down once: open → invite_only.
      {form, []} = SiteForm.handle_key(%{key: :down}, form)
      assert form.drafts["registration_mode"] == "invite_only"

      # Submit (Ctrl-S) and verify Config persists the raw schema string.
      {_form, []} = SiteForm.handle_key(%{key: :char, char: "s", ctrl: true}, form)

      assert Config.get!("registration_mode") == "invite_only"
    end

    test "submit on delivery_mode persists the raw schema string, not the label" do
      sysop = sysop_fixture()
      Config.put!("delivery_mode", "email", nil)

      form =
        SiteForm.init(current_user: sysop)
        |> put_draft("delivery_mode", "no_email")

      {_form, []} = SiteForm.handle_key(%{key: :char, char: "s", ctrl: true}, form)

      raw = Config.get!("delivery_mode")
      assert raw == "no_email"
      refute raw == "No email (offline mode)"
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
