defmodule Foglet.SSH.AccessPolicy do
  @moduledoc """
  SSH hot-path access policy boundary.

  Evaluates source IP allow/deny rules before session creation. Allowlist mode
  means only an explicit allow rule may continue; allowlisted sources still pass
  through global caps and per-IP rate limiting in `Foglet.SSH.CLIHandler`.
  """

  alias Foglet.Config
  alias Foglet.SSH

  @type decision :: {:allow, map()} | {:deny, map()}

  @spec evaluate({:inet.ip_address(), :inet.port_number()} | :unknown) :: decision()
  def evaluate(:unknown), do: evaluate_unknown_peer()

  def evaluate({ip, _port}) when is_tuple(ip) do
    SSH.evaluate_access(ip, allowlist_enabled?: allowlist_enabled?())
  rescue
    _ -> {:allow, %{reason: "policy_unavailable"}}
  end

  def evaluate(_peer), do: evaluate_unknown_peer()

  @spec allowlist_enabled?() :: boolean()
  def allowlist_enabled? do
    case Application.fetch_env(:foglet_bbs, :ssh_ip_allowlist_enabled) do
      {:ok, value} when is_boolean(value) -> value
      _ -> Config.get("ssh_ip_allowlist_enabled", false)
    end
  end

  defp evaluate_unknown_peer do
    if allowlist_enabled?() do
      {:deny, %{reason: "not_allowlisted"}}
    else
      {:allow, %{reason: "unknown_peer"}}
    end
  end
end
