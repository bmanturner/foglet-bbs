defmodule Foglet.Config.SchemaTest do
  # Pure data module — no DB, async OK.
  use ExUnit.Case, async: true

  alias Foglet.Config.InvalidValueError
  alias Foglet.Config.Schema
  alias Foglet.Config.UnknownKeyError

  describe "entries/0" do
    test "returns exactly 12 entries in the documented order" do
      entries = Schema.entries()

      assert length(entries) == 12

      assert Enum.map(entries, & &1.key) == [
               "registration_mode",
               "invite_code_generators",
               "max_post_length",
               "max_thread_title_length",
               "delivery_mode",
               "require_email_verification",
               "guest_mode_enabled",
               "email_verify_resend_cooldown_seconds",
               "invite_generation_per_user_limit",
               "ssh_ip_allowlist_enabled",
               "ssh_rate_limit_max",
               "ssh_rate_limit_window_ms"
             ]
    end

    test "each entry has all required keys with nil-as-appropriate for unused constraints" do
      for spec <- Schema.entries() do
        assert Map.has_key?(spec, :key)
        assert Map.has_key?(spec, :type)
        assert Map.has_key?(spec, :default)
        assert Map.has_key?(spec, :description)
        assert Map.has_key?(spec, :enum)
        assert Map.has_key?(spec, :min)
        assert Map.has_key?(spec, :max)
        assert spec.type in [:string, :integer, :boolean]
        assert is_binary(spec.key)
        assert is_binary(spec.description)
      end
    end

    test "registration_mode spec matches the locked decision table" do
      {:ok, spec} = Schema.fetch_spec("registration_mode")

      assert spec == %{
               key: "registration_mode",
               type: :string,
               default: "open",
               description: "How new accounts are created.",
               enum: ["open", "invite_only", "sysop_approved"],
               min: nil,
               max: nil
             }
    end

    test "invite_code_generators spec matches the locked decision table" do
      {:ok, spec} = Schema.fetch_spec("invite_code_generators")

      assert spec == %{
               key: "invite_code_generators",
               type: :string,
               default: "sysop_only",
               description: "Who can generate invite codes.",
               enum: ["sysop_only", "mods", "any_user"],
               min: nil,
               max: nil
             }
    end

    test "max_post_length spec matches the locked decision table" do
      {:ok, spec} = Schema.fetch_spec("max_post_length")

      assert spec == %{
               key: "max_post_length",
               type: :integer,
               default: 8192,
               description: "Maximum post body length in characters.",
               enum: nil,
               min: 1,
               max: nil
             }
    end

    test "max_thread_title_length spec matches the locked decision table" do
      {:ok, spec} = Schema.fetch_spec("max_thread_title_length")

      assert spec == %{
               key: "max_thread_title_length",
               type: :integer,
               default: 60,
               description: "Maximum thread title length in characters.",
               enum: nil,
               min: 1,
               max: nil
             }
    end

    test "require_email_verification spec matches the locked decision table" do
      {:ok, spec} = Schema.fetch_spec("require_email_verification")

      assert spec == %{
               key: "require_email_verification",
               type: :boolean,
               default: false,
               description: "Verify future users; existing/operators exempt.",
               enum: nil,
               min: nil,
               max: nil
             }
    end

    test "guest_mode_enabled spec matches the locked decision table" do
      {:ok, spec} = Schema.fetch_spec("guest_mode_enabled")

      assert spec == %{
               key: "guest_mode_enabled",
               type: :boolean,
               default: true,
               description:
                 "Allow unauthenticated visitors to enter first-class read-only Guest Mode.",
               enum: nil,
               min: nil,
               max: nil
             }
    end

    test "delivery_mode spec matches the MAIL-01 delivery-mode contract" do
      {:ok, spec} = Schema.fetch_spec("delivery_mode")

      assert spec == %{
               key: "delivery_mode",
               type: :string,
               default: "no_email",
               description: "Whether outbound email is sent.",
               enum: ["email", "no_email"],
               min: nil,
               max: nil
             }
    end

    test "email_verify_resend_cooldown_seconds spec matches the locked decision table" do
      {:ok, spec} = Schema.fetch_spec("email_verify_resend_cooldown_seconds")

      assert spec == %{
               key: "email_verify_resend_cooldown_seconds",
               type: :integer,
               default: 60,
               description: "Minimum seconds between resend-code presses on the Verify screen.",
               enum: nil,
               min: 1,
               max: nil
             }
    end

    test "invite_generation_per_user_limit spec matches the locked decision table" do
      {:ok, spec} = Schema.fetch_spec("invite_generation_per_user_limit")

      assert spec == %{
               key: "invite_generation_per_user_limit",
               type: :integer,
               default: 0,
               description: "Per-user invite cap (0 = unlimited).",
               enum: nil,
               min: 0,
               max: nil
             }
    end

    test "ssh_ip_allowlist_enabled spec matches the access-policy default contract" do
      {:ok, spec} = Schema.fetch_spec("ssh_ip_allowlist_enabled")

      assert spec == %{
               key: "ssh_ip_allowlist_enabled",
               type: :boolean,
               default: false,
               description:
                 "Require an explicit enabled SSH allow rule before a source IP may connect.",
               enum: nil,
               min: nil,
               max: nil
             }
    end

    test "ssh_rate_limit_max spec preserves the legacy per-IP throttle default" do
      {:ok, spec} = Schema.fetch_spec("ssh_rate_limit_max")

      assert spec == %{
               key: "ssh_rate_limit_max",
               type: :integer,
               default: 10,
               description:
                 "Maximum SSH channel startups per source IP within the configured window.",
               enum: nil,
               min: 1,
               max: nil
             }
    end

    test "ssh_rate_limit_window_ms spec preserves the legacy throttle window default" do
      {:ok, spec} = Schema.fetch_spec("ssh_rate_limit_window_ms")

      assert spec == %{
               key: "ssh_rate_limit_window_ms",
               type: :integer,
               default: 60_000,
               description: "SSH per-IP rate limit window in milliseconds.",
               enum: nil,
               min: 1,
               max: nil
             }
    end
  end

  describe "fetch_spec/1" do
    test "returns {:ok, spec} for a known key" do
      assert {:ok, %{key: "registration_mode", type: :string}} =
               Schema.fetch_spec("registration_mode")
    end

    test "returns :error for an unknown key (Map.fetch/2-shaped)" do
      assert Schema.fetch_spec("not_a_real_key") == :error
    end
  end

  describe "defaults/0" do
    test "returns a map of key → default covering exactly the 12 schematized keys" do
      defaults = Schema.defaults()

      assert defaults == %{
               "registration_mode" => "open",
               "invite_code_generators" => "sysop_only",
               "max_post_length" => 8192,
               "max_thread_title_length" => 60,
               "delivery_mode" => "no_email",
               "require_email_verification" => false,
               "guest_mode_enabled" => true,
               "email_verify_resend_cooldown_seconds" => 60,
               "invite_generation_per_user_limit" => 0,
               "ssh_ip_allowlist_enabled" => false,
               "ssh_rate_limit_max" => 10,
               "ssh_rate_limit_window_ms" => 60_000
             }
    end

    test "schema defaults avoid no_email verification dead end" do
      defaults = Schema.defaults()

      assert defaults["delivery_mode"] == "no_email"
      assert defaults["registration_mode"] == "open"
      assert defaults["require_email_verification"] == false
    end
  end

  describe "validate/2 — :ok path" do
    test "accepts every seeded default value" do
      for {key, default} <- Schema.defaults() do
        assert Schema.validate(key, default) == :ok,
               "expected seeded default for #{key} to validate"
      end
    end

    test "accepts each enum member for registration_mode" do
      for v <- ["open", "invite_only", "sysop_approved"] do
        assert Schema.validate("registration_mode", v) == :ok
      end
    end

    test "accepts each enum member for invite_code_generators" do
      for v <- ["sysop_only", "mods", "any_user"] do
        assert Schema.validate("invite_code_generators", v) == :ok
      end
    end

    test "accepts each enum member for delivery_mode" do
      for v <- ["email", "no_email"] do
        assert Schema.validate("delivery_mode", v) == :ok
      end
    end

    test "accepts an integer at the minimum boundary" do
      assert Schema.validate("max_post_length", 1) == :ok
      assert Schema.validate("max_thread_title_length", 1) == :ok
      assert Schema.validate("email_verify_resend_cooldown_seconds", 1) == :ok
    end

    test "accepts a large integer when no max is set" do
      assert Schema.validate("max_post_length", 1_000_000) == :ok
    end

    test "accepts both booleans for require_email_verification" do
      assert Schema.validate("require_email_verification", true) == :ok
      assert Schema.validate("require_email_verification", false) == :ok
    end

    test "accepts both booleans for guest_mode_enabled" do
      assert Schema.validate("guest_mode_enabled", true) == :ok
      assert Schema.validate("guest_mode_enabled", false) == :ok
    end
  end

  describe "validate/2 — type_mismatch" do
    test "rejects an integer for a string key" do
      assert Schema.validate("registration_mode", 42) ==
               {:error, %{reason: :type_mismatch, expected: :string, got: 42}}
    end

    test "rejects a string for an integer key" do
      assert Schema.validate("max_post_length", "nope") ==
               {:error, %{reason: :type_mismatch, expected: :integer, got: "nope"}}
    end

    test "rejects a string for a boolean key" do
      assert Schema.validate("require_email_verification", "true") ==
               {:error, %{reason: :type_mismatch, expected: :boolean, got: "true"}}
    end

    test "rejects a float for an integer key" do
      # :integer type means Elixir integer, not any number
      assert Schema.validate("max_post_length", 8192.0) ==
               {:error, %{reason: :type_mismatch, expected: :integer, got: 8192.0}}
    end
  end

  describe "validate/2 — not_in_enum" do
    test "rejects a value outside the registration_mode enum" do
      assert Schema.validate("registration_mode", "nonsense") ==
               {:error,
                %{
                  reason: :not_in_enum,
                  expected: ["open", "invite_only", "sysop_approved"],
                  got: "nonsense"
                }}
    end

    test "rejects a value outside the invite_code_generators enum" do
      assert Schema.validate("invite_code_generators", "everyone") ==
               {:error,
                %{
                  reason: :not_in_enum,
                  expected: ["sysop_only", "mods", "any_user"],
                  got: "everyone"
                }}
    end

    test "rejects provider names outside the delivery_mode enum" do
      for invalid <- ["smtp", "mailgun"] do
        assert Schema.validate("delivery_mode", invalid) ==
                 {:error,
                  %{
                    reason: :not_in_enum,
                    expected: ["email", "no_email"],
                    got: invalid
                  }}
      end
    end
  end

  describe "validate/2 — below_min (inclusive)" do
    test "rejects an integer below min: 1 for max_post_length" do
      assert Schema.validate("max_post_length", 0) ==
               {:error, %{reason: :below_min, expected: 1, got: 0}}
    end

    test "rejects zero for email_verify_resend_cooldown_seconds (min: 1 per D-02 'minimum seconds')" do
      assert Schema.validate("email_verify_resend_cooldown_seconds", 0) ==
               {:error, %{reason: :below_min, expected: 1, got: 0}}
    end

    test "rejects a negative integer for email_verify_resend_cooldown_seconds" do
      assert Schema.validate("email_verify_resend_cooldown_seconds", -5) ==
               {:error, %{reason: :below_min, expected: 1, got: -5}}
    end
  end

  describe "validate/2 — invalid UTF-8 strings" do
    test "rejects a binary that is not valid UTF-8" do
      # 0xFF 0xFE is an invalid UTF-8 leading-byte sequence. Prevents raw
      # binaries from slipping into jsonb for any future non-enum string key.
      bad = <<0xFF, 0xFE>>

      assert Schema.validate("registration_mode", bad) ==
               {:error, %{reason: :type_mismatch, expected: :string, got: bad}}
    end
  end

  describe "validate/2 — unknown_key" do
    test "returns a tagged error for a key not in the schema" do
      assert Schema.validate("not_a_real_key", "anything") ==
               {:error, {:unknown_key, "not_a_real_key"}}
    end
  end

  describe "UnknownKeyError" do
    test "Exception.message/1 includes the offending key verbatim" do
      msg = Exception.message(%UnknownKeyError{key: "foo"})

      assert msg =~ "unknown config key"
      assert msg =~ ~s("foo")
    end
  end

  describe "InvalidValueError" do
    test "type_mismatch message names key, expected type, and got value" do
      msg =
        Exception.message(%InvalidValueError{
          key: "max_post_length",
          reason: :type_mismatch,
          expected: :integer,
          got: "nope"
        })

      assert msg =~ ~s("max_post_length")
      assert msg =~ ":integer"
      assert msg =~ ~s("nope")
    end

    test "not_in_enum message lists allowed values and got" do
      msg =
        Exception.message(%InvalidValueError{
          key: "registration_mode",
          reason: :not_in_enum,
          expected: ["open", "invite_only", "sysop_approved"],
          got: "bogus"
        })

      assert msg =~ ~s("registration_mode")
      assert msg =~ "open"
      assert msg =~ "invite_only"
      assert msg =~ ~s("bogus")
    end

    test "below_min message mentions the minimum and got" do
      msg =
        Exception.message(%InvalidValueError{
          key: "max_post_length",
          reason: :below_min,
          expected: 1,
          got: 0
        })

      assert msg =~ ~s("max_post_length")
      assert msg =~ "minimum"
      assert msg =~ "1"
      assert msg =~ "0"
    end

    test "above_max message mentions the maximum and got (reserved for future keys)" do
      msg =
        Exception.message(%InvalidValueError{
          key: "future_capped_key",
          reason: :above_max,
          expected: 100,
          got: 999
        })

      assert msg =~ ~s("future_capped_key")
      assert msg =~ "maximum"
      assert msg =~ "100"
      assert msg =~ "999"
    end
  end

  # =========================================================================
  # SYSOP-04 — operator-facing copy hygiene for every Schema description
  # =========================================================================
  #
  # Phase 29 D-22 / D-23: the SITE form renders the @site_keys descriptions to
  # operators, and the LIMITS form renders the @limits_keys descriptions in the
  # same way (sysop_test.exs:845-854 asserts every LimitsForm.limits_keys() spec
  # description appears in the rendered tab). Both surfaces share the same copy
  # rule: descriptions MUST NOT contain planning-ID, phase, pitfall, or
  # deliverable tokens, and MUST end with a period.
  #
  # We sweep every Schema entry rather than a hand-maintained subset so that
  # any future renamed/added key is covered automatically.

  describe "every Schema description is user-facing operator copy (SYSOP-04)" do
    @forbidden_pattern ~r/(D-\d+|REQ-[A-Z]+-\d+|Phase \d+|Pitfall \d+|deliverable)/i

    test "no description contains a planning-ID, phase, pitfall, or deliverable token" do
      for spec <- Schema.entries() do
        description = spec.description

        refute Regex.match?(@forbidden_pattern, description),
               "Description for #{inspect(spec.key)} contains a forbidden token: " <>
                 inspect(description)
      end
    end

    test "every description is non-empty and ends with a period" do
      for spec <- Schema.entries() do
        description = spec.description

        assert is_binary(description) and byte_size(description) > 0,
               "Description for #{inspect(spec.key)} is empty"

        assert String.ends_with?(description, "."),
               "Description for #{inspect(spec.key)} should end with a period: " <>
                 inspect(description)
      end
    end
  end
end
