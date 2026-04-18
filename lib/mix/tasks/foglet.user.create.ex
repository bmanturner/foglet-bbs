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

  alias Foglet.Accounts

  @switches [handle: :string, email: :string, password: :string]

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:foglet_bbs)

    opts =
      try do
        {parsed, _rest} = OptionParser.parse!(args, strict: @switches)
        parsed
      rescue
        e in OptionParser.ParseError ->
          Mix.shell().error("Invalid arguments: #{Exception.message(e)}")
          Mix.shell().error(usage())
          exit({:shutdown, 1})
      end

    handle = Keyword.get(opts, :handle)
    email = Keyword.get(opts, :email)
    password = Keyword.get(opts, :password)

    if is_nil(handle) or is_nil(email) or is_nil(password) do
      Mix.shell().error("Missing required flag.")
      Mix.shell().error(usage())
      exit({:shutdown, 1})
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
        Mix.shell().error("Failed to create user:")

        for {field, errors} <- format_errors(changeset), err <- errors do
          Mix.shell().error("  * #{field}: #{err}")
        end

        exit({:shutdown, 1})
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", if(is_list(v), do: inspect(v), else: to_string(v)))
      end)
    end)
  end

  defp usage do
    """
    Usage:
      mix foglet.user.create --handle HANDLE --email EMAIL --password PASSWORD
    """
  end
end
