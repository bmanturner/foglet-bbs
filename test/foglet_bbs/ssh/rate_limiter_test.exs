defmodule Foglet.SSH.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Foglet.SSH.RateLimiter

  @test_ip_1 {127, 0, 0, 1}
  @test_ip_2 {10, 0, 0, 1}

  # Hammer v7 (ETS backend) creates a named ETS table after the module.
  # The RateLimiter GenServer must be started before any hit/3 calls.
  # We start it once for the whole test module and rely on start_supervised!/1
  # for cleanup between test runs.
  setup_all do
    start_supervised!({RateLimiter, clean_period: :timer.minutes(10)})
    :ok
  end

  # Hammer v7 stores keys as {key, window} tuples in the ETS table named after
  # the module. Delete all entries for a given key string across all windows.
  defp reset_bucket(key) do
    :ets.match_delete(RateLimiter, {{key, :_}, :_, :_})
  end

  setup do
    reset_bucket("ssh:127.0.0.1")
    reset_bucket("ssh:10.0.0.1")
    reset_bucket("ssh:unknown")
    :ok
  end

  test "allows connections under the limit" do
    for _ <- 1..10 do
      assert RateLimiter.allow?({@test_ip_1, 54_321}) == true
    end
  end

  test "denies the 11th connection from the same IP" do
    for _ <- 1..10 do
      RateLimiter.allow?({@test_ip_1, 54_321})
    end

    assert RateLimiter.allow?({@test_ip_1, 54_321}) == false
  end

  test "different IPs have independent buckets" do
    for _ <- 1..10 do
      RateLimiter.allow?({@test_ip_1, 54_321})
    end

    assert RateLimiter.allow?({@test_ip_2, 54_322}) == true
  end

  test "allow? with :unknown peer always fails open, even past the limit" do
    for _ <- 1..11 do
      assert RateLimiter.allow?(:unknown) == true
    end
  end
end
