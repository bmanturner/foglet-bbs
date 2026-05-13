defmodule Foglet.BoardChat.SlashCommands do
  @moduledoc """
  Parses and dispatches board-chat slash commands into normalized message
  payloads.

  Register the next chat slash command in `handlers/0` so composer, permanent,
  and ephemeral send paths all share one domain boundary.
  """

  alias Foglet.BoardChat.Body

  @empty_me_error "Add an action after /me, e.g. /me waves."

  @type payload :: %{kind: :text | :action, body: String.t(), metadata: map()}
  @type error :: {:command_validation, String.t()}

  @doc "Parse trimmed send input into either a plain message or command payload."
  @spec parse(String.t()) :: {:ok, payload()} | {:error, error()}
  def parse(input) when is_binary(input) do
    input = Body.trim(input)

    if String.starts_with?(input, "/") do
      parse_command(input)
    else
      {:ok, %{kind: :text, body: input, metadata: %{}}}
    end
  end

  defp parse_command("/"), do: unknown_command_error("")

  defp parse_command("/" <> rest) do
    {command, args} = split_command(rest)

    case Map.fetch(handlers(), String.downcase(command)) do
      {:ok, handler} -> handler.(args)
      :error -> unknown_command_error(command)
    end
  end

  defp split_command(rest) do
    case String.split(rest, ~r/\s+/, parts: 2, trim: true) do
      [] -> {"", ""}
      [command] -> {command, ""}
      [command, args] -> {command, Body.trim(args)}
    end
  end

  defp handlers do
    %{"me" => &me/1}
  end

  defp me(""), do: {:error, {:command_validation, @empty_me_error}}

  defp me(action) do
    {:ok, %{kind: :action, body: action, metadata: %{"command" => "me"}}}
  end

  defp unknown_command_error(command) do
    displayed = if command == "", do: "/", else: "/#{command}"
    {:error, {:command_validation, "Unknown chat command: #{displayed}. Supported: /me."}}
  end
end
