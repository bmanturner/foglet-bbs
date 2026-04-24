defmodule Mix.Tasks.Foglet.User.ResetPassword do
  @moduledoc """
  Generate an operator break-glass password-reset token for a user.

      mix foglet.user.reset_password bman

  This task is delivery-mode aware. In email mode it prints a break-glass
  reset URL for operator use without sending email. In no-email mode it
  prints explicit operator retrieval details without presenting reset as
  user-facing email delivery.
  """
  @shortdoc "Generate an operator break-glass password-reset URL"

  use Mix.Task

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
        {:ok, url} =
          Accounts.deliver_user_reset_password_instructions(user, &build_reset_url/1)

        Mix.shell().info("Break-glass reset URL for #{user.handle}:")
        Mix.shell().info("  #{url}")

        Mix.shell().info(
          "This URL was generated for operator use; no email was sent by this task."
        )

        :ok

      "no_email" ->
        {:ok, url} =
          Accounts.deliver_user_reset_password_instructions(user, &build_reset_url/1)

        Mix.shell().info("No-email reset details for #{user.handle}:")
        Mix.shell().info("  #{url}")

        Mix.shell().info(
          "This reset URL was generated for operator retrieval; no email was sent by this task."
        )

        :ok
    end
  end

  defp build_reset_url(raw_token) do
    host =
      case Application.get_env(:foglet_bbs, FogletBbsWeb.Endpoint, []) do
        cfg when is_list(cfg) ->
          url_cfg = Keyword.get(cfg, :url, [])
          Keyword.get(url_cfg, :host, "localhost")

        _ ->
          "localhost"
      end

    "https://#{host}/users/reset_password/#{raw_token}"
  end

  defp usage do
    """
    Usage:
      mix foglet.user.reset_password HANDLE
    """
  end
end
