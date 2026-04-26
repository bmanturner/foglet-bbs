defmodule Mix.Tasks.Foglet.User.VerificationCode do
  @moduledoc """
  Generate an operator no-email verification code for an unconfirmed user.

      mix foglet.user.verification_code bman

  This is an explicit no-email retrieval workflow for operators. Email mode
  users should use the normal Login or Verify resend flow.
  """
  @shortdoc "Generate an operator no-email verification code"

  use Mix.Task

  @requirements ["app.config"]

  alias Foglet.Accounts
  alias Foglet.Accounts.User
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
      generate(handle)
    end
  end

  defp generate(handle) do
    case Accounts.get_user_by_handle(handle) do
      nil ->
        MixTaskHelpers.fail("User not found: #{handle}")

      %User{deleted_at: deleted} when not is_nil(deleted) ->
        MixTaskHelpers.fail("User #{handle} has been deleted; cannot generate verification code.")

      %User{confirmed_at: confirmed_at} when not is_nil(confirmed_at) ->
        MixTaskHelpers.fail("User #{handle} is already confirmed.")

      %User{} = user ->
        generate_for_user(user)
    end
  end

  defp generate_for_user(%User{} = user) do
    case Config.delivery_mode() do
      "email" ->
        MixTaskHelpers.fail(
          "Verification delivery is handled by email mode; use the normal Login or Verify resend flow."
        )

      "no_email" ->
        case Accounts.build_verify_code(user) do
          {:ok, code} ->
            Mix.shell().info("No-email verification code for #{user.handle}:")
            Mix.shell().info("  #{code}")

            Mix.shell().info(
              "This verification code was generated for operator retrieval; no email was sent by this task."
            )

            :ok

          {:error, _changeset} ->
            MixTaskHelpers.fail("Could not generate verification code.")
        end
    end
  end

  defp usage do
    """
    Usage:
      mix foglet.user.verification_code HANDLE
    """
  end
end
