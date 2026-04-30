defmodule Mix.Tasks.Foglet.Invites.Revoke do
  @moduledoc """
  Revoke an available invite code.

      mix foglet.invites.revoke INVITE_CODE --actor sysop
  """
  @shortdoc "Revoke an operator/QA invite code"

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
      true -> revoke(actor_handle, code)
    end
  end

  defp revoke(actor_handle, code) do
    with {:ok, actor} <- fetch_actor(actor_handle),
         {:ok, invite} <- Invites.revoke_invite(actor, code) do
      Mix.shell().info("Revoked invite #{invite.code}.")
      :ok
    else
      {:error, :actor_not_found} -> MixTaskHelpers.fail("Actor not found: #{actor_handle}")
      {:error, :forbidden} -> MixTaskHelpers.fail("Forbidden.")
      {:error, :not_found} -> MixTaskHelpers.fail("Invite not found: #{code}")
      {:error, :unavailable} -> MixTaskHelpers.fail("Invite is not available for revocation.")
    end
  end

  defp fetch_actor(handle) do
    case Accounts.get_user_by_handle(handle) do
      nil -> {:error, :actor_not_found}
      actor -> {:ok, actor}
    end
  end

  defp usage do
    """
    Usage:
      mix foglet.invites.revoke INVITE_CODE --actor SYSOP_HANDLE
    """
  end
end
