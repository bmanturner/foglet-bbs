defmodule Foglet.Sessions.OnlineNow do
  @moduledoc """
  Runtime boundary for authenticated Online Now presence.

  Source of truth is `Foglet.Sessions.Registry`, via
  `Foglet.Sessions.Supervisor.online_user_ids/0`. Guest sessions are not
  registered there, so they are naturally excluded from counts and rows.
  """

  alias Foglet.Accounts
  alias Foglet.Sessions.PresenceSummary
  alias Foglet.Sessions.Supervisor, as: SessionSupervisor

  @type row :: %{
          user_id: String.t(),
          handle: String.t(),
          handle_color: String.t() | nil,
          role: atom(),
          presence: PresenceSummary.t(),
          presence_label: String.t(),
          user: map()
        }

  @spec count(keyword()) :: non_neg_integer()
  def count(opts \\ []) do
    opts
    |> online_user_ids()
    |> length()
  end

  @spec list(keyword()) :: [row()]
  def list(opts \\ []) do
    accounts = Keyword.get(opts, :accounts, Accounts)
    presence = Keyword.get(opts, :presence, PresenceSummary)

    opts
    |> online_user_ids()
    |> Enum.flat_map(&row_for_user(&1, accounts, presence, opts))
    |> Enum.sort_by(&sort_key/1)
  end

  defp online_user_ids(opts) do
    sessions = Keyword.get(opts, :sessions, SessionSupervisor)

    sessions.online_user_ids()
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  defp row_for_user(user_id, accounts, presence, opts) do
    case accounts.get_user(user_id) do
      nil ->
        []

      user ->
        summary = presence.for_user(user_id, opts)

        [
          %{
            user_id: user_id,
            handle: handle(user),
            handle_color: handle_color(user),
            role: role(user),
            presence: summary,
            presence_label: presence_label(summary),
            user: user
          }
        ]
    end
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  defp sort_key(%{role: role, handle: handle, user_id: user_id}) do
    {role_rank(role), String.downcase(to_string(handle || "")), user_id}
  end

  defp role_rank(:sysop), do: 0
  defp role_rank(:mod), do: 1
  defp role_rank(_role), do: 2

  defp handle(user), do: Map.get(user, :handle) || Map.get(user, "handle") || "unknown"
  defp handle_color(user), do: Map.get(user, :handle_color) || Map.get(user, "handle_color")
  defp role(user), do: Map.get(user, :role) || Map.get(user, "role") || :user
  defp presence_label(%{label: label}) when is_binary(label), do: label
  defp presence_label(_summary), do: "Online"
end
