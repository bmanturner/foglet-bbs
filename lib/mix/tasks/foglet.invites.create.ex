defmodule Mix.Tasks.Foglet.Invites.Create do
  @moduledoc """
  Create an invite code through the Accounts invite boundary.

      mix foglet.invites.create --actor sysop

  The actor must be permitted by the configured invite policy. The generated
  code is printed once for operator/QA use.
  """
  @shortdoc "Create an operator/QA invite code"

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
      actor_handle -> create(actor_handle)
    end
  end

  defp create(actor_handle) do
    with {:ok, actor} <- fetch_actor(actor_handle),
         {:ok, invite} <- Invites.create_invite(actor) do
      Mix.shell().info("Created invite code:")
      Mix.shell().info("  #{invite.code}")
      Mix.shell().info("Issuer: #{actor.handle} (#{actor.id})")
      :ok
    else
      {:error, :actor_not_found} -> MixTaskHelpers.fail("Actor not found: #{actor_handle}")
      {:error, :forbidden} -> MixTaskHelpers.fail("Forbidden.")
      {:error, :limit_reached} -> MixTaskHelpers.fail("Invite generation limit reached.")
      {:error, changeset} -> MixTaskHelpers.fail_changeset("Failed to create invite:", changeset)
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
      mix foglet.invites.create --actor SYSOP_HANDLE
    """
  end
end
