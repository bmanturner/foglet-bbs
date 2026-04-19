defmodule Mix.Tasks.Foglet.User.ResetPassword do
  @moduledoc """
  Generate a password-reset token for a user and print the reset URL.

      mix foglet.user.reset_password bman

  Phase 1 has no email delivery (CONTEXT D-01/D-03) — the sysop prints
  the URL to stdout and delivers it manually (e.g., via a secure channel).
  Phase 10 wires Swoosh and this task stops being the primary entrypoint.
  """
  @shortdoc "Generate a password-reset URL for a user (stdout, no email)"

  use Mix.Task

  alias Foglet.Accounts
  alias Foglet.Accounts.User

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
        {:ok, url} =
          Accounts.deliver_user_reset_password_instructions(user, &build_reset_url/1)

        Mix.shell().info("Reset URL for #{user.handle}:")
        Mix.shell().info("  #{url}")
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
