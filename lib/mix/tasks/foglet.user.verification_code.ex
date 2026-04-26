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
  alias Foglet.Accounts.{User, Verification}
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
      generate(handle)
    end
  end

  defp generate(handle) do
    case Accounts.get_user_by_handle(handle) do
      nil ->
        Mix.shell().error("User not found: #{handle}")
        exit({:shutdown, 1})

      %User{deleted_at: deleted} when not is_nil(deleted) ->
        Mix.shell().error("User #{handle} has been deleted; cannot generate verification code.")
        exit({:shutdown, 1})

      %User{confirmed_at: confirmed_at} when not is_nil(confirmed_at) ->
        Mix.shell().error("User #{handle} is already confirmed.")
        exit({:shutdown, 1})

      %User{} = user ->
        generate_for_user(user)
    end
  end

  defp generate_for_user(%User{} = user) do
    case Config.delivery_mode() do
      "email" ->
        Mix.shell().error(
          "Verification delivery is handled by email mode; use the normal Login or Verify resend flow."
        )

        exit({:shutdown, 1})

      "no_email" ->
        case Verification.build_verify_code(user) do
          {:ok, code} ->
            Mix.shell().info("No-email verification code for #{user.handle}:")
            Mix.shell().info("  #{code}")

            Mix.shell().info(
              "This verification code was generated for operator retrieval; no email was sent by this task."
            )

            :ok

          {:error, _changeset} ->
            Mix.shell().error("Could not generate verification code.")
            exit({:shutdown, 1})
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
