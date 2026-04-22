defmodule Foglet.Config.SchemaTest do
  # Pure data module — no DB, async OK.
  use ExUnit.Case, async: true

  alias Foglet.Config.InvalidValueError
  alias Foglet.Config.Schema
  alias Foglet.Config.UnknownKeyError

  describe "entries/0" do
    test "returns exactly 6 entries in the documented order" do
      entries = Schema.entries()

      assert length(entries) == 6

      assert Enum.map(entries, & &1.key) == [
               "registration_mode",
               "invite_code_generators",
               "max_post_length",
               "max_thread_title_length",
               "require_email_verification",
               "email_verify_resend_cooldown_seconds"
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
               description:
                 "Account registration policy (D-02/D-03): open | invite_only | sysop_approved",
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
               description: "Who may generate invite codes (D-04): sysop_only | mods | any_user",
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
               description: "Maximum post body length in characters (D-31)",
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
               description:
                 "Maximum thread title length in characters (D-13, phase-03-polish Phase 4)",
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
               default: true,
               description:
                 "When false, new registrations skip verify and existing confirmed_at: nil users gain access on login (Phase 6 D-01)",
               enum: nil,
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
               description:
                 "Minimum seconds between resend-code presses on the Verify screen (Phase 6 D-02)",
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
    test "returns a map of key → default covering exactly the 6 schematized keys" do
      defaults = Schema.defaults()

      assert defaults == %{
               "registration_mode" => "open",
               "invite_code_generators" => "sysop_only",
               "max_post_length" => 8192,
               "max_thread_title_length" => 60,
               "require_email_verification" => true,
               "email_verify_resend_cooldown_seconds" => 60
             }
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
end
