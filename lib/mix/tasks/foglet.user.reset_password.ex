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
  alias Foglet.Accounts.{User, Verification}
  alias Foglet.Config
  alias Foglet.MixTaskHelpers

  @impl Mix.Task
  def run(args) do
    MixTaskHelpers.start_app!()

    {[], positional} = MixTaskHelpers.parse_args!(args, [], usage())

    handle = Enum.at(positional, 0)

    if is_nil(handle) do
      MixTaskHelpers.fail("Missing required handle.", usage())
    else
      reset(handle)
    end
  end

  defp reset(handle) do
    case Accounts.get_user_by_handle(handle) do
      nil ->
        MixTaskHelpers.fail("User not found: #{handle}")

      %User{deleted_at: deleted} when not is_nil(deleted) ->
        MixTaskHelpers.fail("User #{handle} has been deleted; cannot reset password.")

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
    case Verification.generate_reset_token_for_operator(user) do
      {:ok, token} ->
        Mix.shell().info(heading)
        Mix.shell().info("Reset token: #{token}")

        Mix.shell().info(
          "Give this token to the user through your operator-assisted SSH reset procedure."
        )

        Mix.shell().info("No email was sent by this task.")
        :ok

      {:error, changeset} ->
        MixTaskHelpers.fail("Could not generate reset token: #{inspect(changeset.errors)}")
    end
  end

  defp usage do
    """
    Usage:
      mix foglet.user.reset_password HANDLE
    """
  end
end
