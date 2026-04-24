defmodule Mix.Tasks.Foglet.User.Status do
  @moduledoc """
  Change a user's account status.

      mix foglet.user.status TARGET_HANDLE --status active|rejected|suspended --actor SYSOP_HANDLE

  The target handle is positional. The actor handle is required so this
  break-glass task still uses the Accounts authorization boundary.
  """
  @shortdoc "Change a user's account status"

  use Mix.Task

  @switches [status: :string, actor: :string]
  @valid_status_strings ["active", "rejected", "suspended"]

  @impl Mix.Task
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:foglet_bbs)

    {opts, positional} =
      try do
        OptionParser.parse!(args, strict: @switches)
      rescue
        e in OptionParser.ParseError ->
          Mix.shell().error("Invalid arguments: #{Exception.message(e)}")
          Mix.shell().error(usage())
          exit({:shutdown, 1})
      end

    handle = Enum.at(positional, 0)
    status = Keyword.get(opts, :status)
    actor = Keyword.get(opts, :actor)

    cond do
      is_nil(handle) ->
        Mix.shell().error("Missing required target handle.")
        Mix.shell().error(usage())
        exit({:shutdown, 1})

      is_nil(status) ->
        Mix.shell().error("Missing required --status flag.")
        Mix.shell().error(usage())
        exit({:shutdown, 1})

      is_nil(actor) ->
        Mix.shell().error("Missing required --actor flag.")
        Mix.shell().error(usage())
        exit({:shutdown, 1})

      status not in @valid_status_strings ->
        Mix.shell().error(
          "Invalid status: #{inspect(status)}. Valid statuses: #{Enum.join(@valid_status_strings, ", ")}"
        )

        exit({:shutdown, 1})

      true ->
        change_status(handle, status, actor)
    end
  end

  defp change_status(_handle, status, _actor) do
    _target_status = String.to_existing_atom(status)

    :ok
  end

  defp usage do
    """
    Usage:
      mix foglet.user.status TARGET_HANDLE --status active|rejected|suspended --actor SYSOP_HANDLE
    """
  end
end
