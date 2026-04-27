defmodule Foglet.Sessions.Preferences do
  @moduledoc """
  Shared live-session preference snapshots for Phase 5 D-18 through D-21.

  This keeps SSH startup, authenticated promotion, and Account-save refreshes
  on the same shape so active session state cannot drift from persisted user
  preferences.
  """

  alias Foglet.Accounts.User
  alias Foglet.TUI.Theme

  @default_timezone "Etc/UTC"
  @default_time_format "12h"
  @default_theme_id "gray"

  @type snapshot :: %{
          timezone: String.t(),
          time_format: String.t(),
          theme_id: String.t(),
          theme: Theme.t()
        }

  @doc """
  Builds the display preference snapshot used by active TUI sessions.
  """
  @spec from_user(User.t() | nil) :: snapshot()
  def from_user(nil) do
    default_snapshot()
  end

  def from_user(%User{} = user) do
    timezone =
      Map.get(user, :timezone) ||
        Application.get_env(:foglet_bbs, :default_timezone) ||
        @default_timezone
    time_format = get_in(user.preferences || %{}, ["time_format"]) || @default_time_format
    {theme_id, theme} = resolve_theme(user.theme)

    %{
      timezone: timezone,
      time_format: time_format,
      theme_id: theme_id,
      theme: theme
    }
  end

  defp default_snapshot do
    %{
      timezone: Application.get_env(:foglet_bbs, :default_timezone) || @default_timezone,
      time_format: @default_time_format,
      theme_id: @default_theme_id,
      theme: Theme.default()
    }
  end

  defp resolve_theme(theme_id) when is_binary(theme_id) do
    Theme.ids()
    |> Enum.find(&(Atom.to_string(&1) == theme_id))
    |> case do
      nil -> {@default_theme_id, Theme.default()}
      atom_id -> {theme_id, Theme.resolve(atom_id)}
    end
  end

  defp resolve_theme(_theme_id), do: {@default_theme_id, Theme.default()}
end
