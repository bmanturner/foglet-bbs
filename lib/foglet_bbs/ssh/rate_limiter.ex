defmodule Foglet.SSH.RateLimiter do
  @moduledoc """
  Per-IP SSH connection rate limiter backed by Hammer v7 (ETS).

  Enforces @rate_limit_max connections per @rate_limit_window_ms per source IP.
  This module uses `use Hammer, backend: :ets` which injects `start_link/1` and
  `hit/3`. It must be started as a child process before use — `Foglet.SSH.Supervisor`
  adds it to its supervision tree.

  ## Usage

      # Check and increment rate limit for a peer
      Foglet.SSH.RateLimiter.allow?({127, 0, 0, 1})  # => true | false

  Fails open on any unexpected error to maintain SSH daemon availability.
  """

  use Hammer, backend: :ets

  @default_rate_limit_max 10
  @default_rate_limit_window_ms 60_000

  @spec allow?(peer :: {:inet.ip_address(), :inet.port_number()} | :unknown) :: boolean()
  # Fail open when peer address is unresolvable — no address to gate on.
  def allow?(:unknown), do: true

  def allow?(peer) do
    key = ip_key(peer)

    case hit(key, rate_limit_window_ms(), rate_limit_max()) do
      {:allow, _count} -> true
      {:deny, _retry_after_ms} -> false
    end
  rescue
    # Fail open if the ETS table is unavailable (e.g. RateLimiter restarting).
    _ -> true
  end

  def rate_limit_max do
    runtime_value(:ssh_rate_limit_max, "ssh_rate_limit_max", @default_rate_limit_max)
  end

  def rate_limit_window_ms do
    runtime_value(
      :ssh_rate_limit_window_ms,
      "ssh_rate_limit_window_ms",
      @default_rate_limit_window_ms
    )
  end

  @spec ip_key(peer :: {:inet.ip_address(), :inet.port_number()}) :: String.t()
  defp ip_key({ip_tuple, _port}) when is_tuple(ip_tuple) do
    "ssh:" <> (ip_tuple |> :inet.ntoa() |> to_string())
  end

  defp runtime_value(env_key, config_key, default) do
    case Application.fetch_env(:foglet_bbs, env_key) do
      {:ok, value} when is_integer(value) -> value
      _ -> Foglet.Config.get(config_key, default)
    end
  rescue
    _ -> default
  end
end
