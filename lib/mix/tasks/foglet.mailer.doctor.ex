defmodule Mix.Tasks.Foglet.Mailer.Doctor do
  @moduledoc """
  Diagnose Foglet transactional email configuration.

      mix foglet.mailer.doctor
      mix foglet.mailer.doctor --to sysop@example.com

  Without `--to`, the task prints resolved mailer configuration and does not
  send mail. With `--to`, it attempts one diagnostic delivery.
  """
  @shortdoc "Diagnose transactional email delivery"

  use Mix.Task

  @requirements ["app.config"]

  alias Foglet.Mailer.Doctor
  alias Foglet.MixTaskHelpers

  @switches [to: :string]

  @impl Mix.Task
  def run(args) do
    {opts, positional} = MixTaskHelpers.parse_args!(args, @switches, usage())

    if positional != [] do
      MixTaskHelpers.fail(
        "Unexpected positional arguments: #{Enum.join(positional, " ")}",
        usage()
      )
    end

    case Doctor.run(opts) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        MixTaskHelpers.fail("Mailer doctor failed: #{inspect(reason)}")
    end
  end

  defp usage do
    """
    Usage:
      mix foglet.mailer.doctor [--to EMAIL]
    """
  end
end
