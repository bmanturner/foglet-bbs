defmodule Mix.Tasks.Foglet.Users.Reject do
  @moduledoc """
  Reject a pending user through the Accounts status boundary.

      mix foglet.users.reject TARGET_HANDLE --actor sysop
  """
  @shortdoc "Reject a pending operator/QA user"

  use Mix.Task

  @requirements ["app.config"]

  alias Foglet.Accounts
  alias Foglet.MixTaskHelpers

  @switches [actor: :string]

  @impl Mix.Task
  def run(args) do
    MixTaskHelpers.start_app!()

    {opts, positional} = MixTaskHelpers.parse_args!(args, @switches, usage())

    target_handle = Enum.at(positional, 0)
    actor_handle = Keyword.get(opts, :actor)

    cond do
      is_nil(target_handle) -> MixTaskHelpers.fail("Missing required target handle.", usage())
      is_nil(actor_handle) -> MixTaskHelpers.fail("Missing required --actor flag.", usage())
      true -> transition(target_handle, actor_handle)
    end
  end

  defp transition(target_handle, actor_handle) do
    actor = Accounts.get_user_by_handle(actor_handle)

    case Accounts.transition_user_status(actor, target_handle, :rejected) do
      {:ok, %{user: updated, from: :pending, to: :rejected, delivery: delivery}} ->
        Mix.shell().info("Rejected #{updated.handle}. Notification: #{format_delivery(delivery)}")

        :ok

      {:ok, %{from: from, to: to}} ->
        MixTaskHelpers.fail("Unexpected status transition from #{from} to #{to}.")

      {:error, :forbidden} ->
        MixTaskHelpers.fail("Forbidden.")

      {:error, :not_found} ->
        MixTaskHelpers.fail("User not found.")

      {:error, :deleted} ->
        MixTaskHelpers.fail("Deleted users cannot be rejected.")

      {:error, :invalid_transition} ->
        MixTaskHelpers.fail("Only pending users can be rejected.")

      {:error, :invalid_status} ->
        MixTaskHelpers.fail("Invalid target status.")
    end
  end

  defp format_delivery(:not_applicable), do: "not_applicable"
  defp format_delivery(:skipped_no_email), do: "skipped_no_email"
  defp format_delivery(:attempted), do: "attempted"
  defp format_delivery({:failed, _reason}), do: "failed"

  defp usage do
    """
    Usage:
      mix foglet.users.reject TARGET_HANDLE --actor SYSOP_HANDLE
    """
  end
end
