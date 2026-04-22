defmodule Foglet.ConfigTest do
  # async: false because :foglet_config is a shared named ETS table.
  use FogletBbs.DataCase, async: false

  alias Foglet.Config
  alias Foglet.Config.Entry

  @test_keys [
    "test.key.string",
    "test.key.integer",
    "test.key.bool",
    "test.key.missing"
  ]

  setup do
    Config.init_cache()
    # Clean any keys this test will touch for isolation
    for key <- @test_keys, do: Config.invalidate(key)
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
      Config.put!("test.key.string", "hello", nil)
      assert Config.get!("test.key.string") == "hello"
    end

    test "round-trips a boolean value" do
      Config.put!("test.key.bool", false, nil)
      assert Config.get!("test.key.bool") == false
    end

    test "round-trips an integer value" do
      Config.put!("test.key.integer", 42, nil)
      assert Config.get!("test.key.integer") == 42
    end

    test "get!/1 caches in ETS — second read is served from cache" do
      Config.put!("test.key.string", "cached", nil)
      _ = Config.get!("test.key.string")

      # Mutate DB directly, bypassing Config.put! (which would invalidate)
      Entry
      |> Repo.get_by!(key: "test.key.string")
      |> Ecto.Changeset.change(%{value: %{"v" => "DB_ONLY"}})
      |> Repo.update!()

      # ETS still has the old value
      assert Config.get!("test.key.string") == "cached"

      # After explicit invalidation the new value is read
      Config.invalidate("test.key.string")
      assert Config.get!("test.key.string") == "DB_ONLY"
    end

    test "put!/3 invalidates the ETS cache" do
      Config.put!("test.key.string", "first", nil)
      assert Config.get!("test.key.string") == "first"

      Config.put!("test.key.string", "second", nil)
      assert Config.get!("test.key.string") == "second"
    end
  end

  describe "get!/1 on missing key" do
    test "raises Ecto.NoResultsError" do
      assert_raise Ecto.NoResultsError, fn ->
        Config.get!("test.key.missing")
      end
    end
  end

  describe "get/2" do
    test "returns the default when the key is absent from the DB" do
      assert Config.get("test.key.missing", :fallback) == :fallback
    end

    test "returns the stored value when the key is present" do
      Config.put!("test.key.string", "present", nil)
      assert Config.get("test.key.string", :fallback) == "present"
    end
  end
end
