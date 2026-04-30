defmodule Mix.Tasks.Foglet.Invites.List do
  @moduledoc """
  List invite codes and lifecycle state for operator/QA inspection.

      mix foglet.invites.list --actor sysop
  """
  @shortdoc "List operator/QA invite codes"

  use Mix.Task

  @requirements ["app.config"]

  alias Foglet.Accounts
  alias Foglet.Accounts.Invites
  alias Foglet.MixTaskHelpers

  @switches [actor: :string]

  @impl Mix.Task
  def run(args) do
    MixTaskHelpers.start_app!()

    {opts, _positional} = MixTaskHelpers.parse_args!(args, @switches, usage())

    case Keyword.get(opts, :actor) do
      nil -> MixTaskHelpers.fail("Missing required --actor flag.", usage())
      actor_handle -> list(actor_handle)
    end
  end

  defp list(actor_handle) do
    with {:ok, actor} <- fetch_actor(actor_handle),
         {:ok, invites} <- Invites.list_invites(actor) do
      Enum.each(invites, &print_invite/1)
      if invites == [], do: Mix.shell().info("No invite codes found.")
      :ok
    else
      {:error, :actor_not_found} -> MixTaskHelpers.fail("Actor not found: #{actor_handle}")
      {:error, :forbidden} -> MixTaskHelpers.fail("Forbidden.")
    end
  end

  defp fetch_actor(handle) do
    case Accounts.get_user_by_handle(handle) do
      nil -> {:error, :actor_not_found}
      actor -> {:ok, actor}
    end
  end

  defp print_invite(invite) do
    Mix.shell().info(
      Enum.join(
        [
          "code=#{invite.code}",
          "status=#{invite.status}",
          "issuer_id=#{invite.issuer_id}",
          "inserted_at=#{DateTime.to_iso8601(invite.inserted_at)}",
          "consumed_at=#{format_datetime(invite.consumed_at)}",
          "revoked_at=#{format_datetime(invite.revoked_at)}"
        ],
        " "
      )
    )
  end

  defp format_datetime(nil), do: "nil"
  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp usage do
    """
    Usage:
      mix foglet.invites.list --actor SYSOP_HANDLE
    """
  end
end
