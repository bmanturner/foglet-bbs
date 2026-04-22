defmodule Foglet.ConfigTest do
  # async: false because :foglet_config is a shared named ETS table.
  use FogletBbs.DataCase, async: false

  alias Foglet.Config
  alias Foglet.Config.Entry
  alias Foglet.Config.InvalidValueError
  alias Foglet.Config.UnknownKeyError

  # Real schema keys — the DB is seeded with these via priv/repo/seeds.exs,
  # but DataCase uses the Ecto sandbox so test mutations do not escape.
  @test_keys [
    "registration_mode",
    "max_post_length",
    "require_email_verification"
  ]

  setup do
    Config.init_cache()
    # ETS is process-global (the sandbox only rolls back the DB), so drop
    # cached values both before and after each test to guarantee that the
    # next read hits the sandbox-visible DB state.
    for key <- @test_keys, do: Config.invalidate(key)
    on_exit(fn -> for key <- @test_keys, do: Config.invalidate(key) end)
    :ok
  end

  describe "init_cache/0" do
    test "is idempotent across invocations" do
      assert :ok = Config.init_cache()
      assert :ok = Config.init_cache()
      assert :ets.whereis(:foglet_config) != :undefined
    end
  end

  describe "put!/3 + get!/1" do
    test "round-trips a string value through the DB" do
      Config.put!("registration_mode", "invite_only", nil)
      assert Config.get!("registration_mode") == "invite_only"
    end

    test "round-trips a boolean value" do
      Config.put!("require_email_verification", false, nil)
      assert Config.get!("require_email_verification") == false
    end

    test "round-trips an integer value" do
      Config.put!("max_post_length", 4096, nil)
      assert Config.get!("max_post_length") == 4096
    end

    test "get!/1 caches in ETS — second read is served from cache" do
      Config.put!("registration_mode", "open", nil)
      _ = Config.get!("registration_mode")

      # Mutate DB directly, bypassing Config.put! (which would invalidate).
      # Use a valid enum value so we're only exercising cache-staleness, not
      # the semantic question "is this value legal".
      Entry
      |> Repo.get_by!(key: "registration_mode")
      |> Ecto.Changeset.change(%{value: %{"v" => "invite_only"}})
      |> Repo.update!()

      # ETS still has the old value.
      assert Config.get!("registration_mode") == "open"

      # After explicit invalidation the new value is read.
      Config.invalidate("registration_mode")
      assert Config.get!("registration_mode") == "invite_only"
    end

    test "put!/3 invalidates the ETS cache" do
      Config.put!("max_post_length", 4096, nil)
      assert Config.get!("max_post_length") == 4096

      Config.put!("max_post_length", 2048, nil)
      assert Config.get!("max_post_length") == 2048
    end
  end

  describe "get!/1 on missing key" do
    test "raises Ecto.NoResultsError" do
      # Delete the seeded row so the next read misses in both ETS and DB.
      Repo.delete_all(from e in Entry, where: e.key == "registration_mode")
      Config.invalidate("registration_mode")

      assert_raise Ecto.NoResultsError, fn ->
        Config.get!("registration_mode")
      end
    end
  end

  describe "get/2" do
    test "returns the default when the key is absent from the DB" do
      Repo.delete_all(from e in Entry, where: e.key == "registration_mode")
      Config.invalidate("registration_mode")

      assert Config.get("registration_mode", :fallback) == :fallback
    end

    test "returns the stored value when the key is present" do
      Config.put!("registration_mode", "invite_only", nil)
      assert Config.get("registration_mode", :fallback) == "invite_only"
    end
  end

  describe "fetch/1" do
    test "returns {:ok, value} when the key is present" do
      Config.put!("max_post_length", 1234, nil)
      assert Config.fetch("max_post_length") == {:ok, 1234}
    end

    test "returns :error when the key is absent from the DB" do
      Repo.delete_all(from e in Entry, where: e.key == "max_post_length")
      Config.invalidate("max_post_length")

      assert Config.fetch("max_post_length") == :error
    end

    test "uses the ETS cache on the present path (second call does not hit DB)" do
      Config.put!("registration_mode", "invite_only", nil)
      assert {:ok, "invite_only"} = Config.fetch("registration_mode")

      # Mutate the DB directly — a cached hit should still return the old value.
      Entry
      |> Repo.get_by!(key: "registration_mode")
      |> Ecto.Changeset.change(%{value: %{"v" => "sysop_approved"}})
      |> Repo.update!()

      assert {:ok, "invite_only"} = Config.fetch("registration_mode")
    end
  end

  describe "put!/3 validation" do
    test "raises UnknownKeyError for a key not in the schema" do
      err =
        assert_raise UnknownKeyError, fn ->
          Config.put!("definitely_not_a_schema_key", 1, nil)
        end

      assert err.key == "definitely_not_a_schema_key"
      assert Exception.message(err) =~ ~s("definitely_not_a_schema_key")
    end

    test "unknown-key rejection does not touch the DB" do
      before_count = Repo.aggregate(Entry, :count, :id)

      assert_raise UnknownKeyError, fn ->
        Config.put!("definitely_not_a_schema_key", 1, nil)
      end

      assert Repo.aggregate(Entry, :count, :id) == before_count
    end

    test "raises InvalidValueError on type mismatch" do
      err =
        assert_raise InvalidValueError, fn ->
          Config.put!("max_post_length", "nope", nil)
        end

      assert err.key == "max_post_length"
      assert err.reason == :type_mismatch
      assert err.expected == :integer
      assert err.got == "nope"
    end

    test "raises InvalidValueError on enum violation" do
      err =
        assert_raise InvalidValueError, fn ->
          Config.put!("registration_mode", "bogus", nil)
        end

      assert err.key == "registration_mode"
      assert err.reason == :not_in_enum
      assert err.expected == ["open", "invite_only", "sysop_approved"]
      assert err.got == "bogus"
    end

    test "raises InvalidValueError on range violation (below min)" do
      err =
        assert_raise InvalidValueError, fn ->
          Config.put!("max_post_length", 0, nil)
        end

      assert err.key == "max_post_length"
      assert err.reason == :below_min
      assert err.expected == 1
      assert err.got == 0
    end

    test "does not touch DB on validation failure" do
      # Snapshot value + description before attempting a bad write.
      before_row = Repo.get_by!(Entry, key: "registration_mode")

      assert_raise InvalidValueError, fn ->
        Config.put!("registration_mode", "bogus", nil)
      end

      after_row = Repo.get_by!(Entry, key: "registration_mode")
      assert after_row.value == before_row.value
      assert after_row.description == before_row.description
    end

    test "accepts a valid boolean update" do
      # Starts seeded to true.
      Config.put!("require_email_verification", false, nil)
      assert Config.get!("require_email_verification") == false
    end
  end

  describe "typed accessors" do
    test "registration_mode/0 returns the seeded default" do
      assert Config.registration_mode() == "open"
    end

    test "invite_code_generators/0 returns the seeded default" do
      assert Config.invite_code_generators() == "sysop_only"
    end

    test "max_post_length/0 returns the seeded default" do
      assert Config.max_post_length() == 8192
    end

    test "max_thread_title_length/0 returns the seeded default" do
      assert Config.max_thread_title_length() == 60
    end

    test "require_email_verification?/0 returns the seeded default with ? suffix" do
      assert Config.require_email_verification?() == true
      # Confirm the predicate (?) name is the one exported — a compile error
      # here would mean the accessor was named without the ? suffix.
      assert function_exported?(Config, :require_email_verification?, 0)
    end

    test "email_verify_resend_cooldown_seconds/0 returns the seeded default" do
      assert Config.email_verify_resend_cooldown_seconds() == 60
    end

    test "typed accessor reflects subsequent writes" do
      Config.put!("max_post_length", 2048, nil)
      assert Config.max_post_length() == 2048
    end
  end
end
