defmodule Mix.Tasks.Foglet.User.ResetPassword do
  @moduledoc """
  Generate an operator break-glass password-reset token for a user.

      mix foglet.user.reset_password bman

  This task is delivery-mode aware. In email mode it prints a break-glass
  reset token for operator use without sending email. In no-email mode it
  prints explicit operator retrieval details without presenting reset as
  user-facing email delivery.
  """
  @shortdoc "Generate an operator break-glass password-reset token"

  use Mix.Task

  @requirements ["app.config"]

  alias Foglet.Accounts
  alias Foglet.Accounts.User
  alias Foglet.Config

  @impl Mix.Task
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:foglet_bbs)

    {[], positional} =
      try do
        OptionParser.parse!(args, strict: [])
      rescue
        e in OptionParser.ParseError ->
          Mix.shell().error("Invalid arguments: #{Exception.message(e)}")
          Mix.shell().error(usage())
          exit({:shutdown, 1})
      end

    handle = Enum.at(positional, 0)

    if is_nil(handle) do
      Mix.shell().error("Missing required handle.")
      Mix.shell().error(usage())
      exit({:shutdown, 1})
    else
      reset(handle)
    end
  end

  defp reset(handle) do
    case Accounts.get_user_by_handle(handle) do
      nil ->
        Mix.shell().error("User not found: #{handle}")
        exit({:shutdown, 1})

      %User{deleted_at: deleted} when not is_nil(deleted) ->
        Mix.shell().error("User #{handle} has been deleted; cannot reset password.")
        exit({:shutdown, 1})

      %User{} = user ->
        reset_existing_user(user)
    end
  end

  defp reset_existing_user(%User{} = user) do
    case Config.delivery_mode() do
      "email" ->
        print_reset_token(user, "Break-glass reset token for #{user.handle}:")

      "no_email" ->
        print_reset_token(user, "No-email reset details for #{user.handle}:")
    end
  end

  defp print_reset_token(%User{} = user, heading) do
    case Accounts.generate_reset_token_for_operator(user) do
      {:ok, token} ->
        Mix.shell().info(heading)
        Mix.shell().info("Reset token: #{token}")

        Mix.shell().info(
          "Give this token to the user through your operator-assisted SSH reset procedure."
        )

        Mix.shell().info("No email was sent by this task.")
        :ok

      {:error, changeset} ->
        Mix.shell().error("Could not generate reset token: #{inspect(changeset.errors)}")
        exit({:shutdown, 1})
    end
  end

  defp usage do
    """
    Usage:
      mix foglet.user.reset_password HANDLE
    """
  end
end
