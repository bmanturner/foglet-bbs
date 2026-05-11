defmodule Foglet.Doors.SecurityLevel do
  @moduledoc false

  @type level :: 50 | 90 | 100

  @spec for_role(term()) :: level()
  def for_role(role) do
    case normalize_role(role) do
      "sysop" -> 100
      "mod" -> 90
      _other -> 50
    end
  end

  @spec for_role_string(term()) :: String.t()
  def for_role_string(role), do: role |> for_role() |> Integer.to_string()

  defp normalize_role(role) when is_atom(role), do: role |> Atom.to_string() |> normalize_role()

  defp normalize_role(role) when is_binary(role) do
    role
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_role(_role), do: ""
end
