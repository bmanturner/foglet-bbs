defmodule Foglet.TUI.RoleBadge do
  @moduledoc """
  Central role-badge labels for reusable public/admin TUI surfaces.
  """

  @spec badge(atom() | String.t() | nil) :: String.t() | nil
  def badge(:sysop), do: "✹ SYSOP"
  def badge("sysop"), do: "✹ SYSOP"
  def badge(:mod), do: "✦ MOD"
  def badge("mod"), do: "✦ MOD"
  def badge(_role), do: nil

  @spec compact(atom() | String.t() | nil) :: String.t()
  def compact(role), do: badge(role) || role_label(role)

  defp role_label(nil), do: "user"
  defp role_label(role), do: to_string(role)
end
