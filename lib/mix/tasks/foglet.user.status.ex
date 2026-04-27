defmodule Mix.Tasks.Foglet.User.Status do
  @moduledoc """
  Change a user's account status.

      mix foglet.user.status TARGET_HANDLE --status active|rejected|suspended --actor SYSOP_HANDLE

  The target handle is positional. The actor handle is required so this
  break-glass task still uses the Accounts authorization boundary.
  """
  @shortdoc "Change a user's account status"

  use Mix.Task

  @requirements ["app.config"]

  alias Foglet.Accounts
  alias Foglet.MixTaskHelpers

  @switches [status: :string, actor: :string]
  @valid_status_strings ["active", "rejected", "suspended"]

  @impl Mix.Task
  def run(args) do
    MixTaskHelpers.start_app!()

    {opts, positional} = MixTaskHelpers.parse_args!(args, @switches, usage())

    handle = Enum.at(positional, 0)
    status = Keyword.get(opts, :status)
    actor = Keyword.get(opts, :actor)

    cond do
      is_nil(handle) ->
        MixTaskHelpers.fail("Missing required target handle.", usage())

      is_nil(status) ->
        MixTaskHelpers.fail("Missing required --status flag.", usage())

      is_nil(actor) ->
        MixTaskHelpers.fail("Missing required --actor flag.", usage())

      status not in @valid_status_strings ->
        MixTaskHelpers.fail(
          "Invalid status: #{inspect(status)}. Valid statuses: #{Enum.join(@valid_status_strings, ", ")}"
        )

      true ->
        change_status(handle, status, actor)
    end
  end

  defp change_status(handle, status, actor_handle) do
    target_status = String.to_existing_atom(status)

    case Accounts.get_user_by_handle(actor_handle) do
      nil -> fail("User not found.")
      actor -> transition_status(actor, handle, target_status)
    end
  end

  defp transition_status(actor, handle, target_status) do
    case Accounts.transition_user_status(actor, handle, target_status) do
      {:ok, %{user: updated, from: from, to: to, delivery: delivery}} ->
        Mix.shell().info(
          "Changed #{updated.handle} from #{from} to #{to}. Notification: #{format_delivery(delivery)}"
        )

        :ok

      {:error, :forbidden} ->
        fail("Forbidden.")

      {:error, :not_found} ->
        fail("User not found.")

      {:error, :deleted} ->
        fail("Deleted users cannot be changed.")

      {:error, :invalid_transition} ->
        fail("Invalid status transition.")

      {:error, :invalid_status} ->
        fail("Invalid target status.")
    end
  end

  defp format_delivery(:not_applicable), do: "not_applicable"
  defp format_delivery(:skipped_no_email), do: "skipped_no_email"
  defp format_delivery(:attempted), do: "attempted"
  defp format_delivery({:failed, _reason}), do: "failed"

  @spec fail(String.t()) :: no_return()
  defp fail(message), do: MixTaskHelpers.fail(message)

  defp usage do
    """
    Usage:
      mix foglet.user.status TARGET_HANDLE --status active|rejected|suspended --actor SYSOP_HANDLE
    """
  end
end
