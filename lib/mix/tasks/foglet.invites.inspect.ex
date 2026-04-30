defmodule Mix.Tasks.Foglet.Invites.Inspect do
  @moduledoc """
  Inspect a single invite code and lifecycle state.

      mix foglet.invites.inspect INVITE_CODE --actor sysop
  """
  @shortdoc "Inspect an operator/QA invite code"

  use Mix.Task

  @requirements ["app.config"]

  alias Foglet.Accounts
  alias Foglet.Accounts.Invites
  alias Foglet.MixTaskHelpers

  @switches [actor: :string]

  @impl Mix.Task
  def run(args) do
    MixTaskHelpers.start_app!()

    {opts, positional} = MixTaskHelpers.parse_args!(args, @switches, usage())

    code = Enum.at(positional, 0)
    actor_handle = Keyword.get(opts, :actor)

    cond do
      is_nil(code) -> MixTaskHelpers.fail("Missing required invite code.", usage())
      is_nil(actor_handle) -> MixTaskHelpers.fail("Missing required --actor flag.", usage())
      true -> inspect_invite(actor_handle, code)
    end
  end

  defp inspect_invite(actor_handle, code) do
    with {:ok, actor} <- fetch_actor(actor_handle),
         {:ok, invites} <- Invites.list_invites(actor),
         invite when not is_nil(invite) <- Enum.find(invites, &(&1.code == code)) do
      print_invite(invite)
      :ok
    else
      {:error, :actor_not_found} -> MixTaskHelpers.fail("Actor not found: #{actor_handle}")
      {:error, :forbidden} -> MixTaskHelpers.fail("Forbidden.")
      nil -> MixTaskHelpers.fail("Invite not found: #{code}")
    end
  end

  defp fetch_actor(handle) do
    case Accounts.get_user_by_handle(handle) do
      nil -> {:error, :actor_not_found}
      actor -> {:ok, actor}
    end
  end

  defp print_invite(invite) do
    Mix.shell().info("Invite code: #{invite.code}")
    Mix.shell().info("Status: #{invite.status}")
    Mix.shell().info("Issuer ID: #{invite.issuer_id}")
    Mix.shell().info("Inserted at: #{DateTime.to_iso8601(invite.inserted_at)}")
    Mix.shell().info("Consumed at: #{format_datetime(invite.consumed_at)}")
    Mix.shell().info("Consumed by user ID: #{inspect(invite.consumed_by_user_id)}")
    Mix.shell().info("Revoked at: #{format_datetime(invite.revoked_at)}")
  end

  defp format_datetime(nil), do: "nil"
  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp usage do
    """
    Usage:
      mix foglet.invites.inspect INVITE_CODE --actor SYSOP_HANDLE
    """
  end
end
