defmodule Foglet.Accounts.ShortCode do
  @moduledoc """
  Cryptographically generated short user-facing codes.

  Codes use the product-contract alphabet `A-Z`, `a-z`, and `0-9`.
  Rejection sampling avoids modulo bias when mapping random bytes onto the
  62-character alphabet.
  """

  @alphabet String.to_charlist("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
  @alphabet_size length(@alphabet)
  @max_unbiased_byte 256 - rem(256, @alphabet_size)

  @spec generate(pos_integer()) :: String.t()
  def generate(length) when is_integer(length) and length > 0 do
    length
    |> generate_chars([])
    |> Enum.reverse()
    |> to_string()
  end

  defp generate_chars(0, chars), do: chars

  defp generate_chars(remaining, chars) do
    remaining
    |> random_bytes_for_remaining()
    |> take_unbiased_chars(remaining, chars)
  end

  defp random_bytes_for_remaining(remaining), do: :crypto.strong_rand_bytes(remaining * 2)

  defp take_unbiased_chars(<<>>, remaining, chars), do: generate_chars(remaining, chars)

  defp take_unbiased_chars(_bytes, 0, chars), do: chars

  defp take_unbiased_chars(<<byte, rest::binary>>, remaining, chars)
       when byte < @max_unbiased_byte do
    char = Enum.at(@alphabet, rem(byte, @alphabet_size))
    take_unbiased_chars(rest, remaining - 1, [char | chars])
  end

  defp take_unbiased_chars(<<_byte, rest::binary>>, remaining, chars) do
    take_unbiased_chars(rest, remaining, chars)
  end
end
