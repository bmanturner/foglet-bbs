defmodule Foglet.TUI.Screens.Sysop.ConfigAccountabilityTest do
  use FogletBbs.DataCase, async: false

  alias Foglet.Config.Schema
  alias Foglet.TUI.Screens.Sysop.LimitsForm
  alias Foglet.TUI.Screens.Sysop.SiteForm

  describe "visibility ledger" do
    test "D-04 accounts for every schema key and no unknown keys" do
      schema_keys = Schema.entries() |> Enum.map(& &1.key) |> MapSet.new()
      ledger_keys = visibility_ledger() |> Enum.map(&elem(&1, 0)) |> MapSet.new()

      assert ledger_keys == schema_keys
    end

    test "D-05 only uses launch accountability status values" do
      allowed = MapSet.new([:visible, :conditionally_visible, :intentionally_hidden, :non_pre_alpha])

      statuses =
        visibility_ledger()
        |> Enum.map(fn {_key, {status, _reason}} -> status end)
        |> MapSet.new()

      assert MapSet.subset?(statuses, allowed)
    end

    test "D-06 classifies SITE always-visible controls as visible" do
      assert ledger_status("registration_mode") == :visible
      assert ledger_status("invite_code_generators") == :visible
      assert ledger_status("delivery_mode") == :visible
      assert ledger_status("require_email_verification") == :visible
    end

    test "D-06 classifies invite per-user limit as conditionally visible" do
      assert {"invite_generation_per_user_limit",
              {:conditionally_visible,
               "Visible only when invite_code_generators == \"any_user\"; affects invite generation cap through Foglet.Config.invite_generation_per_user_limit/0"}} in visibility_ledger()
    end

    test "D-06 classifies LIMITS controls as visible" do
      assert ledger_status("max_post_length") == :visible
      assert ledger_status("max_thread_title_length") == :visible
      assert ledger_status("email_verify_resend_cooldown_seconds") == :visible
    end

    test "D-04 keeps Sysop form key lists disjoint and equal to schema keys" do
      schema_keys = Schema.entries() |> Enum.map(& &1.key) |> MapSet.new()
      site_keys = SiteForm.site_keys() |> MapSet.new()
      limits_keys = LimitsForm.limits_keys() |> MapSet.new()

      assert MapSet.disjoint?(site_keys, limits_keys)
      assert MapSet.union(site_keys, limits_keys) == schema_keys
    end
  end

  defp ledger_status(key) do
    visibility_ledger()
    |> List.keyfind!(key, 0)
    |> elem(1)
    |> elem(0)
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
       {:visible, "LIMITS control affects post body validation through Foglet.Config.max_post_length/0"}},
      {"max_thread_title_length",
       {:visible,
        "LIMITS control affects thread title validation through Foglet.Config.max_thread_title_length/0"}},
      {"email_verify_resend_cooldown_seconds",
       {:visible,
        "LIMITS control affects Verify resend cooldown through Foglet.Config.email_verify_resend_cooldown_seconds/0"}}
    ]
  end
end
