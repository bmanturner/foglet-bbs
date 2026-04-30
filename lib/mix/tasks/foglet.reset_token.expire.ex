defmodule Mix.Tasks.Foglet.ResetToken.Expire do
  @moduledoc """
  Force the latest reset token for a user outside its validity window.

      mix foglet.reset_token.expire HANDLE

  Use this operator/QA task to exercise expired reset-token handling without
  waiting for the normal reset-token lifetime.
  """
  @shortdoc "Expire latest reset token for QA"

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
      handle -> expire(handle)
    end
  end

  defp expire(handle) do
    case Accounts.get_user_by_handle(handle) do
      nil ->
        MixTaskHelpers.fail("User not found: #{handle}")

      %User{deleted_at: deleted_at} when not is_nil(deleted_at) ->
        MixTaskHelpers.fail("User #{handle} has been deleted; cannot expire reset token.")

      %User{} = user ->
        expire_for_user(user)
    end
  end

  defp expire_for_user(%User{} = user) do
    case Verification.expire_latest_reset_token_for_operator(user) do
      {:ok, token} ->
        Mix.shell().info("Expired latest reset token for #{user.handle}.")
        Mix.shell().info("Inserted at: #{DateTime.to_iso8601(token.inserted_at)}")
        :ok

      {:error, :not_found} ->
        MixTaskHelpers.fail("No reset token found for #{user.handle}.")

      {:error, changeset} ->
        MixTaskHelpers.fail("Could not expire reset token: #{inspect(changeset.errors)}")
    end
  end

  defp usage do
    """
    Usage:
      mix foglet.reset_token.expire HANDLE
    """
  end
end
