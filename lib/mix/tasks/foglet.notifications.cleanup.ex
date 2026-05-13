defmodule Mix.Tasks.Foglet.Notifications.Cleanup do
  @moduledoc """
  Delete read notifications older than an explicit retention window.

      mix foglet.notifications.cleanup --days 30

  The window is measured from `read_at`. Unread notifications are never deleted
  by this task, even when their `inserted_at` timestamp is older than the
  retention window.
  """
  @shortdoc "Delete old read notifications"

  use Mix.Task

  @requirements ["app.config"]

  alias Foglet.MixTaskHelpers
  alias Foglet.Notifications

  @switches [days: :integer]

  @impl Mix.Task
  def run(args) do
    MixTaskHelpers.start_app!()

    {opts, positional} = MixTaskHelpers.parse_args!(args, @switches, usage())

    if positional == [] do
      cleanup!(Keyword.get(opts, :days))
    else
      MixTaskHelpers.fail(
        "Unexpected positional arguments: #{Enum.join(positional, " ")}",
        usage()
      )
    end
  end

  defp cleanup!(days) when is_integer(days) and days > 0 do
    case Notifications.cleanup_read_notifications(days) do
      {:ok, count} ->
        Mix.shell().info(
          "Deleted #{count} read notifications older than #{days} #{day_label(days)}."
        )

      {:error, :invalid_retention_days} ->
        MixTaskHelpers.fail(
          "Invalid --days #{inspect(days)}. Provide a positive integer.",
          usage()
        )
    end
  end

  defp cleanup!(nil), do: MixTaskHelpers.fail("Provide --days with a positive integer.", usage())

  defp cleanup!(days),
    do:
      MixTaskHelpers.fail("Invalid --days #{inspect(days)}. Provide a positive integer.", usage())

  defp day_label(1), do: "day"
  defp day_label(_days), do: "days"

  defp usage do
    """
    Usage:
      mix foglet.notifications.cleanup --days POSITIVE_INTEGER
    """
  end
end
