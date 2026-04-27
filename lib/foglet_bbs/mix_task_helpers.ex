defmodule Foglet.MixTaskHelpers do
  @moduledoc """
  Shared boilerplate for `mix foglet.*` tasks.
  """

  @doc """
  Start the `:foglet_bbs` OTP application. Called at the top of each task's
  `run/1` before any domain work.
  """
  def start_app! do
    {:ok, _} = Application.ensure_all_started(:foglet_bbs)
    :ok
  end

  @doc """
  Parse argv with OptionParser. On parse failure, prints the error message and
  usage text (if provided), then exits non-zero.
  """
  def parse_args!(argv, switches, usage \\ nil) do
    OptionParser.parse!(argv, strict: switches)
  rescue
    e in OptionParser.ParseError ->
      fail("Invalid arguments: " <> Exception.message(e), usage)
  end

  @doc "Format `Ecto.Changeset` errors into a `%{field => [string]}` map."
  def format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(
          acc,
          "%{" <> to_string(k) <> "}",
          if(is_list(v), do: inspect(v), else: to_string(v))
        )
      end)
    end)
  end

  @doc """
  Print an error message (and optional detail string) to the shell, then exit
  non-zero. Never returns.
  """
  @spec fail(String.t()) :: no_return()
  @spec fail(String.t(), String.t() | nil) :: no_return()
  def fail(message, detail \\ nil) do
    Mix.shell().error(message)
    if detail, do: Mix.shell().error(detail)
    exit({:shutdown, 1})
  end

  @doc """
  Print an error heading, then each field/error pair from a changeset, then
  exit non-zero. Never returns.
  """
  @spec fail_changeset(String.t(), Ecto.Changeset.t()) :: no_return()
  def fail_changeset(message, changeset) do
    Mix.shell().error(message)

    for {field, errors} <- format_errors(changeset), err <- errors do
      Mix.shell().error("  * #{field}: #{err}")
    end

    exit({:shutdown, 1})
  end
end
