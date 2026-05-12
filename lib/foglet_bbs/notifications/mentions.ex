defmodule Foglet.Notifications.Mentions do
  @moduledoc """
  Conservative @handle parsing for durable mention notifications.
  """

  @handle_regex ~r/(^|[^A-Za-z0-9_@-])@([A-Za-z0-9][A-Za-z0-9_-]{1,19})(?![A-Za-z0-9_-])/

  @doc """
  Extracts unique mention handles from `body` in first-seen order.

  Matching follows `Foglet.Accounts.User` handle characters and length, requires
  the `@` not be embedded in an email/word token, and dedupes case-insensitively.
  """
  @spec extract_handles(String.t() | nil) :: [String.t()]
  def extract_handles(body) when is_binary(body) do
    @handle_regex
    |> Regex.scan(body, capture: :all_but_first)
    |> Enum.map(fn [_prefix, handle] -> handle end)
    |> Enum.reduce({MapSet.new(), []}, fn handle, {seen, acc} ->
      key = String.downcase(handle)

      if MapSet.member?(seen, key) do
        {seen, acc}
      else
        {MapSet.put(seen, key), [handle | acc]}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  def extract_handles(_body), do: []
end
