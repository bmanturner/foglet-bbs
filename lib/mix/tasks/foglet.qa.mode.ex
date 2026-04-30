defmodule Mix.Tasks.Foglet.Qa.Mode do
  @moduledoc """
  Set registration QA mode keys through the trusted runtime-config path.

      mix foglet.qa.mode --registration-mode open --require-email-verification false --delivery-mode no_email

  This task exists for reproducible QA matrix setup. It is not a user-facing
  product workflow.
  """
  @shortdoc "Set QA registration mode config"

  use Mix.Task

  @requirements ["app.config"]

  alias Foglet.Config
  alias Foglet.MixTaskHelpers

  @switches [
    registration_mode: :string,
    require_email_verification: :string,
    delivery_mode: :string
  ]

  @impl Mix.Task
  def run(args) do
    MixTaskHelpers.start_app!()

    {opts, positional} = MixTaskHelpers.parse_args!(args, @switches, usage())

    cond do
      positional != [] ->
        MixTaskHelpers.fail(
          "Unexpected positional arguments: #{Enum.join(positional, " ")}",
          usage()
        )

      opts == [] ->
        MixTaskHelpers.fail("Provide at least one mode switch.", usage())

      true ->
        apply_mode(opts)
    end
  end

  defp apply_mode(opts) do
    opts
    |> Enum.each(fn
      {:registration_mode, value} ->
        put!("registration_mode", value)

      {:require_email_verification, value} ->
        put!("require_email_verification", parse_bool!(value))

      {:delivery_mode, value} ->
        put!("delivery_mode", value)
    end)

    Mix.shell().info("QA mode updated:")

    Mix.shell().info(
      "registration_mode=#{Config.registration_mode()} " <>
        "require_email_verification=#{Config.require_email_verification?()} " <>
        "delivery_mode=#{Config.delivery_mode()}"
    )

    :ok
  end

  defp parse_bool!("true"), do: true
  defp parse_bool!("false"), do: false

  defp parse_bool!(value) do
    MixTaskHelpers.fail(
      "Invalid require-email-verification value: #{inspect(value)}. Use true or false."
    )
  end

  defp put!(key, value) do
    Config.put!(key, value, nil)
  rescue
    e in [Foglet.Config.UnknownKeyError, Foglet.Config.InvalidValueError] ->
      MixTaskHelpers.fail(Exception.message(e))
  end

  defp usage do
    """
    Usage:
      mix foglet.qa.mode [--registration-mode open|invite_only|sysop_approved] [--require-email-verification true|false] [--delivery-mode no_email|email]
    """
  end
end
