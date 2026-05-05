defmodule Foglet.BoardChat.Body do
  @moduledoc """
  Shared validation contract for chat message bodies.

  Permanent and ephemeral chat paths both use this module as the single source
  of truth for body trimming and maximum character length before storage or
  broadcast.
  """

  @max_length 4_000

  @type validation_error :: :body_blank | :body_too_long

  @doc "Maximum allowed message body length, in characters."
  @spec max_length() :: 4_000
  def max_length, do: @max_length

  @doc "Trim a body before validation/storage."
  @spec trim(term()) :: term()
  def trim(nil), do: nil
  def trim(body) when is_binary(body), do: String.trim(body)
  def trim(other), do: other

  @doc "Validate a binary body after trimming."
  @spec validate(term()) :: {:ok, String.t()} | {:error, validation_error()}
  def validate(body) when is_binary(body) do
    trimmed = trim(body)

    cond do
      trimmed == "" -> {:error, :body_blank}
      String.length(trimmed) > @max_length -> {:error, :body_too_long}
      true -> {:ok, trimmed}
    end
  end

  def validate(_body), do: {:error, :body_blank}
end
