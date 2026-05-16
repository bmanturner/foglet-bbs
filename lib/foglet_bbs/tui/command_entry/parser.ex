defmodule Foglet.TUI.CommandEntry.Parser do
  @moduledoc """
  Pure parser for the global command entry surface.
  """

  @type parsed ::
          {:search, String.t()}
          | {:direct_post, String.t(), pos_integer()}
          | {:slash, String.t(), String.t()}

  @spec parse(term()) :: {:ok, parsed()} | {:error, atom()}
  def parse(input) when is_binary(input) do
    input = String.trim(input)

    cond do
      input == "" ->
        {:error, :blank}

      String.starts_with?(input, "/") ->
        parse_slash(input)

      String.contains?(input, ":") ->
        parse_direct_post(input)

      true ->
        {:ok, {:search, input}}
    end
  end

  def parse(_input), do: {:error, :invalid_input}

  defp parse_slash("/"), do: {:error, :empty_slash_command}

  defp parse_slash("/" <> rest) do
    case String.split(String.trim(rest), ~r/\s+/, parts: 2) do
      [""] -> {:error, :empty_slash_command}
      [command] -> {:ok, {:slash, String.downcase(command), ""}}
      [command, args] -> {:ok, {:slash, String.downcase(command), String.trim(args)}}
    end
  end

  defp parse_direct_post(input) do
    with [slug, number_text] <- String.split(input, ":", parts: 2),
         true <- Regex.match?(~r/^[A-Za-z0-9_-]+$/, slug),
         {number, ""} when number > 0 <- Integer.parse(String.trim(number_text)) do
      {:ok, {:direct_post, String.downcase(slug), number}}
    else
      _ -> {:error, :malformed_direct_post}
    end
  end
end
