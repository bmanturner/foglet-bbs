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

  @switches [role: :string]
  @valid_role_strings ["user", "mod", "sysop"]

  @impl Mix.Task
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:foglet_bbs)

    {opts, positional} =
      try do
        OptionParser.parse!(args, strict: @switches)
      rescue
        e in OptionParser.ParseError ->
          Mix.shell().error("Invalid arguments: #{Exception.message(e)}")
          Mix.shell().error(usage())
          exit({:shutdown, 1})
      end

    handle = Enum.at(positional, 0)
    role_str = Keyword.get(opts, :role)

    cond do
      is_nil(handle) ->
        Mix.shell().error("Missing required handle.")
        Mix.shell().error(usage())
        exit({:shutdown, 1})

      is_nil(role_str) ->
        Mix.shell().error("Missing required --role flag.")
        Mix.shell().error(usage())
        exit({:shutdown, 1})

      role_str not in @valid_role_strings ->
        Mix.shell().error(
          "Invalid role: #{inspect(role_str)}. Valid roles: #{Enum.join(@valid_role_strings, ", ")}"
        )

        exit({:shutdown, 1})

      true ->
        promote(handle, role_str)
    end
  end

  defp promote(handle, role_str) do
    case Accounts.get_user_by_handle(handle) do
      nil ->
        Mix.shell().error("User not found: #{handle}")
        exit({:shutdown, 1})

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
        Mix.shell().error("Failed to promote #{handle}:")

        for {field, errors} <- format_errors(changeset), err <- errors do
          Mix.shell().error("  * #{field}: #{err}")
        end

        exit({:shutdown, 1})
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
  end

  defp usage do
    """
    Usage:
      mix foglet.user.promote HANDLE --role user|mod|sysop
    """
  end
end
