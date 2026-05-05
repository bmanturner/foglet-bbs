defmodule Foglet.TerminalText do
  @moduledoc """
  Helpers for converting user/operator-controlled text into terminal-safe plain text.

  Foglet's primary product surface is an SSH terminal. Any plain text that can
  reach Raxol `text/2` from persisted or user-controlled data must not preserve
  terminal-control bytes, because those bytes can move the cursor, restyle the
  display, spoof prompts, or trigger OSC features such as clipboard writes.
  """

  @type text :: String.t()

  @doc """
  Removes terminal-control bytes from plain text while preserving printable text.

  Preserves newline and tab as intentional layout whitespace. Other C0 controls,
  DEL, C1 controls, raw ESC, CSI sequences, and OSC sequences terminated by BEL,
  ST (`ESC \\`), or C1 ST are removed.
  """
  @spec sanitize_plain_text(text()) :: text()
  def sanitize_plain_text(text) when is_binary(text) do
    sanitize_binary(text, [])
  end

  defp sanitize_binary(<<>>, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  # OSC: ESC ] ... BEL / ESC \\ / C1 ST
  defp sanitize_binary(<<0x1B, ?], rest::binary>>, acc) do
    rest |> drop_osc_payload() |> sanitize_binary(acc)
  end

  # CSI: ESC [ parameter/intermediate bytes final-byte
  defp sanitize_binary(<<0x1B, ?[, rest::binary>>, acc) do
    rest |> drop_control_sequence() |> sanitize_binary(acc)
  end

  # Other ESC-prefixed control sequences. Drop through the first printable final byte.
  defp sanitize_binary(<<0x1B, rest::binary>>, acc) do
    rest |> drop_control_sequence() |> sanitize_binary(acc)
  end

  # 8-bit OSC / CSI variants. These bytes are invalid UTF-8 but can exist in binaries.
  defp sanitize_binary(<<0x9D, rest::binary>>, acc) do
    rest |> drop_osc_payload() |> sanitize_binary(acc)
  end

  defp sanitize_binary(<<0x9B, rest::binary>>, acc) do
    rest |> drop_control_sequence() |> sanitize_binary(acc)
  end

  # Preserve layout whitespace that renderers intentionally understand.
  defp sanitize_binary(<<byte, rest::binary>>, acc) when byte in [?\n, ?\t] do
    sanitize_binary(rest, [<<byte>> | acc])
  end

  # Strip C0 controls and DEL encoded as single bytes.
  defp sanitize_binary(<<byte, rest::binary>>, acc) when byte in 0x00..0x1F or byte == 0x7F do
    sanitize_binary(rest, acc)
  end

  # Preserve valid UTF-8 text by codepoint so multibyte printable characters are
  # not corrupted by their continuation bytes. Strip C1 controls if they arrive
  # as valid Unicode codepoints.
  defp sanitize_binary(<<codepoint::utf8, rest::binary>>, acc)
       when codepoint in 0x80..0x9F do
    sanitize_binary(rest, acc)
  end

  defp sanitize_binary(<<codepoint::utf8, rest::binary>>, acc) do
    sanitize_binary(rest, [<<codepoint::utf8>> | acc])
  end

  # Invalid/non-UTF-8 bytes should not reach text rendering. Strip C1 bytes and
  # preserve other bytes as a best-effort fallback.
  defp sanitize_binary(<<byte, rest::binary>>, acc) when byte in 0x80..0x9F do
    sanitize_binary(rest, acc)
  end

  defp sanitize_binary(<<byte, rest::binary>>, acc) do
    sanitize_binary(rest, [<<byte>> | acc])
  end

  defp drop_osc_payload(<<>>), do: <<>>
  defp drop_osc_payload(<<0x07, rest::binary>>), do: rest
  defp drop_osc_payload(<<0x9C, rest::binary>>), do: rest
  defp drop_osc_payload(<<0x1B, ?\\, rest::binary>>), do: rest
  defp drop_osc_payload(<<_byte, rest::binary>>), do: drop_osc_payload(rest)

  defp drop_control_sequence(<<>>), do: <<>>

  defp drop_control_sequence(<<byte, rest::binary>>) when byte in 0x40..0x7E do
    rest
  end

  defp drop_control_sequence(<<_byte, rest::binary>>), do: drop_control_sequence(rest)
end
