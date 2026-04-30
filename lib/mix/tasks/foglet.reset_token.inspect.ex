defmodule Mix.Tasks.Foglet.ResetToken.Inspect do
  @moduledoc """
  Issue a fresh no-email reset token for operator/QA inspection.

      mix foglet.reset_token.inspect HANDLE

  Reset-token rows store only SHA256 hashes, so the latest raw reset token
  cannot be reconstructed. This task preserves that invariant and prints a
  fresh raw token for the no-email operator-assisted reset flow.
  """
  @shortdoc "Issue fresh no-email reset token"

  use Mix.Task

  @requirements ["app.config"]

  alias Foglet.Accounts
  alias Foglet.Accounts.{User, Verification}
  alias Foglet.MixTaskHelpers

  @impl Mix.Task
  def run(args) do
    MixTaskHelpers.start_app!()

    {[], positional} = MixTaskHelpers.parse_args!(args, [], usage())

    case Enum.at(positional, 0) do
      nil -> MixTaskHelpers.fail("Missing required handle.", usage())
      handle -> inspect_token(handle)
    end
  end

  defp inspect_token(handle) do
    case Accounts.get_user_by_handle(handle) do
      nil ->
        MixTaskHelpers.fail("User not found: #{handle}")

      %User{deleted_at: deleted_at} when not is_nil(deleted_at) ->
        MixTaskHelpers.fail("User #{handle} has been deleted; cannot generate reset token.")

      %User{status: status} when status != :active ->
        MixTaskHelpers.fail(
          "User #{handle} is #{status}; reset token requires an active account."
        )

      %User{} = user ->
        print_fresh_token(user)
    end
  end

  defp print_fresh_token(%User{} = user) do
    case Verification.generate_no_email_reset_token_for_operator(user) do
      {:ok, token} ->
        Mix.shell().info("Fresh no-email reset token for #{user.handle}:")
        Mix.shell().info("Reset token: #{token}")

        Mix.shell().info(
          "Reset tokens are stored hashed; this fresh raw token is the only inspectable value."
        )

        :ok

      {:error, :unavailable} ->
        MixTaskHelpers.fail(
          "Reset-token inspection is only available when delivery_mode is no_email."
        )

      {:error, changeset} ->
        MixTaskHelpers.fail("Could not generate reset token: #{inspect(changeset.errors)}")
    end
  end

  defp usage do
    """
    Usage:
      mix foglet.reset_token.inspect HANDLE
    """
  end
end
