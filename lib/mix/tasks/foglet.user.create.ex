defmodule Mix.Tasks.Foglet.User.Create do
  @moduledoc """
  Create a user account from the command line.

      mix foglet.user.create --handle bman --email bman@example.com --password secret123

  Sysop-created accounts are auto-confirmed per CONTEXT D-02 — no email
  verification token is generated.

  All three flags are required. Missing or unknown flags exit non-zero
  with a usage message.
  """
  @shortdoc "Create a user account (sysop-only, auto-confirmed)"

  use Mix.Task

  @requirements ["app.config"]

  alias Foglet.Accounts
  alias Foglet.MixTaskHelpers

  @switches [handle: :string, email: :string, password: :string]

  @impl Mix.Task
  def run(args) do
    MixTaskHelpers.start_app!()

    {opts, _rest} = MixTaskHelpers.parse_args!(args, @switches, usage())

    handle = Keyword.get(opts, :handle)
    email = Keyword.get(opts, :email)
    password = Keyword.get(opts, :password)

    if is_nil(handle) or is_nil(email) or is_nil(password) do
      MixTaskHelpers.fail("Missing required flag.", usage())
    else
      create_user(handle, email, password)
    end
  end

  defp create_user(handle, email, password) do
    case Accounts.register_user(%{handle: handle, email: email, password: password}) do
      {:ok, user} ->
        # D-02: auto-confirm sysop-created accounts
        {:ok, confirmed} = Accounts.confirm_user(user)
        Mix.shell().info("Created user #{confirmed.handle} (#{confirmed.id})")
        :ok

      {:error, changeset} ->
        MixTaskHelpers.fail_changeset("Failed to create user:", changeset)
    end
  end

  defp usage do
    """
    Usage:
      mix foglet.user.create --handle HANDLE --email EMAIL --password PASSWORD
    """
  end
end
