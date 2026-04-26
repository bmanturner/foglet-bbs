defmodule Mix.Tasks.Foglet.User.Promote do
  @moduledoc """
  Assign a role (user, mod, sysop) to an existing user.

      mix foglet.user.promote bman --role sysop

  The handle is a positional argument; the role is a `--role` flag.
  Valid roles are: user, mod, sysop (CONTEXT D-05).
  """
  @shortdoc "Assign a role to an existing user"

  use Mix.Task

  @requirements ["app.config"]

  alias Foglet.Accounts
  alias Foglet.Accounts.User
  alias Foglet.MixTaskHelpers

  @switches [role: :string]
  @valid_role_strings ["user", "mod", "sysop"]

  @impl Mix.Task
  def run(args) do
    MixTaskHelpers.start_app!()

    {opts, positional} = MixTaskHelpers.parse_args!(args, @switches, usage())

    handle = Enum.at(positional, 0)
    role_str = Keyword.get(opts, :role)

    cond do
      is_nil(handle) ->
        MixTaskHelpers.fail("Missing required handle.", usage())

      is_nil(role_str) ->
        MixTaskHelpers.fail("Missing required --role flag.", usage())

      role_str not in @valid_role_strings ->
        MixTaskHelpers.fail(
          "Invalid role: #{inspect(role_str)}. Valid roles: #{Enum.join(@valid_role_strings, ", ")}"
        )

      true ->
        promote(handle, role_str)
    end
  end

  defp promote(handle, role_str) do
    case Accounts.get_user_by_handle(handle) do
      nil ->
        MixTaskHelpers.fail("User not found: #{handle}")

      %User{} = user ->
        apply_role(user, handle, role_str)
    end
  end

  defp apply_role(user, handle, role_str) do
    case Accounts.update_role(user, role_str) do
      {:ok, updated} ->
        Mix.shell().info("Promoted #{updated.handle} to #{updated.role}")
        :ok

      {:error, changeset} ->
        MixTaskHelpers.fail_changeset("Failed to promote #{handle}:", changeset)
    end
  end

  defp usage do
    """
    Usage:
      mix foglet.user.promote HANDLE --role user|mod|sysop
    """
  end
end
