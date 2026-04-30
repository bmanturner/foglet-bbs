defmodule Mix.Tasks.Foglet.Verification.Inspect do
  @moduledoc """
  Inspect the latest unexpired no-email verification code for a user.

      mix foglet.verification.inspect HANDLE

  This is an operator/QA break-glass task for `delivery_mode = no_email`.
  In email mode, use the normal Login or Verify resend flow.
  """
  @shortdoc "Inspect latest no-email verification code"

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
      handle -> inspect_code(handle)
    end
  end

  defp inspect_code(handle) do
    case Accounts.get_user_by_handle(handle) do
      nil ->
        MixTaskHelpers.fail("User not found: #{handle}")

      %User{deleted_at: deleted_at} when not is_nil(deleted_at) ->
        MixTaskHelpers.fail("User #{handle} has been deleted; cannot inspect verification code.")

      %User{confirmed_at: confirmed_at} when not is_nil(confirmed_at) ->
        MixTaskHelpers.fail("User #{handle} is already confirmed.")

      %User{} = user ->
        print_latest_code(user)
    end
  end

  defp print_latest_code(%User{} = user) do
    case Verification.latest_no_email_verify_code(user) do
      {:ok, %{code: code, inserted_at: inserted_at, expires_at: expires_at}} ->
        Mix.shell().info("Latest no-email verification code for #{user.handle}:")
        Mix.shell().info("  #{code}")
        Mix.shell().info("Inserted at: #{DateTime.to_iso8601(inserted_at)}")
        Mix.shell().info("Expires at: #{DateTime.to_iso8601(expires_at)}")
        :ok

      {:error, :unavailable} ->
        MixTaskHelpers.fail(
          "Verification inspection is only available when delivery_mode is no_email."
        )

      {:error, :not_found} ->
        MixTaskHelpers.fail("No unexpired no-email verification code found for #{user.handle}.")
    end
  end

  defp usage do
    """
    Usage:
      mix foglet.verification.inspect HANDLE
    """
  end
end
