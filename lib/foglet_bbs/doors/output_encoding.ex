defmodule Foglet.Doors.OutputEncoding do
  @moduledoc """
  Terminal-output transcoding for external door processes.

  Most modern Foglet-owned doors emit UTF-8. Classic BBS doors may still emit
  IBM code page 437 for splash art and box drawing. SSH clients expect UTF-8, so
  CP437 bytes must be translated before they are written to the channel.
  """

  @type encoding :: :utf8 | :cp437

  @cp437 %{
    0x80 => <<0xC7::utf8>>,
    0x81 => <<0xFC::utf8>>,
    0x82 => <<0xE9::utf8>>,
    0x83 => <<0xE2::utf8>>,
    0x84 => <<0xE4::utf8>>,
    0x85 => <<0xE0::utf8>>,
    0x86 => <<0xE5::utf8>>,
    0x87 => <<0xE7::utf8>>,
    0x88 => <<0xEA::utf8>>,
    0x89 => <<0xEB::utf8>>,
    0x8A => <<0xE8::utf8>>,
    0x8B => <<0xEF::utf8>>,
    0x8C => <<0xEE::utf8>>,
    0x8D => <<0xEC::utf8>>,
    0x8E => <<0xC4::utf8>>,
    0x8F => <<0xC5::utf8>>,
    0x90 => <<0xC9::utf8>>,
    0x91 => <<0xE6::utf8>>,
    0x92 => <<0xC6::utf8>>,
    0x93 => <<0xF4::utf8>>,
    0x94 => <<0xF6::utf8>>,
    0x95 => <<0xF2::utf8>>,
    0x96 => <<0xFB::utf8>>,
    0x97 => <<0xF9::utf8>>,
    0x98 => <<0xFF::utf8>>,
    0x99 => <<0xD6::utf8>>,
    0x9A => <<0xDC::utf8>>,
    0x9B => <<0xA2::utf8>>,
    0x9C => <<0xA3::utf8>>,
    0x9D => <<0xA5::utf8>>,
    0x9E => <<0x20A7::utf8>>,
    0x9F => <<0x192::utf8>>,
    0xA0 => <<0xE1::utf8>>,
    0xA1 => <<0xED::utf8>>,
    0xA2 => <<0xF3::utf8>>,
    0xA3 => <<0xFA::utf8>>,
    0xA4 => <<0xF1::utf8>>,
    0xA5 => <<0xD1::utf8>>,
    0xA6 => <<0xAA::utf8>>,
    0xA7 => <<0xBA::utf8>>,
    0xA8 => <<0xBF::utf8>>,
    0xA9 => <<0x2310::utf8>>,
    0xAA => <<0xAC::utf8>>,
    0xAB => <<0xBD::utf8>>,
    0xAC => <<0xBC::utf8>>,
    0xAD => <<0xA1::utf8>>,
    0xAE => <<0xAB::utf8>>,
    0xAF => <<0xBB::utf8>>,
    0xB0 => <<0x2591::utf8>>,
    0xB1 => <<0x2592::utf8>>,
    0xB2 => <<0x2593::utf8>>,
    0xB3 => <<0x2502::utf8>>,
    0xB4 => <<0x2524::utf8>>,
    0xB5 => <<0x2561::utf8>>,
    0xB6 => <<0x2562::utf8>>,
    0xB7 => <<0x2556::utf8>>,
    0xB8 => <<0x2555::utf8>>,
    0xB9 => <<0x2563::utf8>>,
    0xBA => <<0x2551::utf8>>,
    0xBB => <<0x2557::utf8>>,
    0xBC => <<0x255D::utf8>>,
    0xBD => <<0x255C::utf8>>,
    0xBE => <<0x255B::utf8>>,
    0xBF => <<0x2510::utf8>>,
    0xC0 => <<0x2514::utf8>>,
    0xC1 => <<0x2534::utf8>>,
    0xC2 => <<0x252C::utf8>>,
    0xC3 => <<0x251C::utf8>>,
    0xC4 => <<0x2500::utf8>>,
    0xC5 => <<0x253C::utf8>>,
    0xC6 => <<0x255E::utf8>>,
    0xC7 => <<0x255F::utf8>>,
    0xC8 => <<0x255A::utf8>>,
    0xC9 => <<0x2554::utf8>>,
    0xCA => <<0x2569::utf8>>,
    0xCB => <<0x2566::utf8>>,
    0xCC => <<0x2560::utf8>>,
    0xCD => <<0x2550::utf8>>,
    0xCE => <<0x256C::utf8>>,
    0xCF => <<0x2567::utf8>>,
    0xD0 => <<0x2568::utf8>>,
    0xD1 => <<0x2564::utf8>>,
    0xD2 => <<0x2565::utf8>>,
    0xD3 => <<0x2559::utf8>>,
    0xD4 => <<0x2558::utf8>>,
    0xD5 => <<0x2552::utf8>>,
    0xD6 => <<0x2553::utf8>>,
    0xD7 => <<0x256B::utf8>>,
    0xD8 => <<0x256A::utf8>>,
    0xD9 => <<0x2518::utf8>>,
    0xDA => <<0x250C::utf8>>,
    0xDB => <<0x2588::utf8>>,
    0xDC => <<0x2584::utf8>>,
    0xDD => <<0x258C::utf8>>,
    0xDE => <<0x2590::utf8>>,
    0xDF => <<0x2580::utf8>>,
    0xE0 => <<0x3B1::utf8>>,
    0xE1 => <<0xDF::utf8>>,
    0xE2 => <<0x393::utf8>>,
    0xE3 => <<0x3C0::utf8>>,
    0xE4 => <<0x3A3::utf8>>,
    0xE5 => <<0x3C3::utf8>>,
    0xE6 => <<0xB5::utf8>>,
    0xE7 => <<0x3C4::utf8>>,
    0xE8 => <<0x3A6::utf8>>,
    0xE9 => <<0x398::utf8>>,
    0xEA => <<0x3A9::utf8>>,
    0xEB => <<0x3B4::utf8>>,
    0xEC => <<0x221E::utf8>>,
    0xED => <<0x3C6::utf8>>,
    0xEE => <<0x3B5::utf8>>,
    0xEF => <<0x2229::utf8>>,
    0xF0 => <<0x2261::utf8>>,
    0xF1 => <<0xB1::utf8>>,
    0xF2 => <<0x2265::utf8>>,
    0xF3 => <<0x2264::utf8>>,
    0xF4 => <<0x2320::utf8>>,
    0xF5 => <<0x2321::utf8>>,
    0xF6 => <<0xF7::utf8>>,
    0xF7 => <<0x2248::utf8>>,
    0xF8 => <<0xB0::utf8>>,
    0xF9 => <<0x2219::utf8>>,
    0xFA => <<0xB7::utf8>>,
    0xFB => <<0x221A::utf8>>,
    0xFC => <<0x207F::utf8>>,
    0xFD => <<0xB2::utf8>>,
    0xFE => <<0x25A0::utf8>>,
    0xFF => <<0xA0::utf8>>
  }

  @doc "Converts door output bytes to the SSH terminal's UTF-8 stream."
  @spec to_terminal(binary(), encoding()) :: binary()
  def to_terminal(data, :utf8) when is_binary(data) do
    {output, pending} = to_terminal(data, :utf8, "")
    output <> cp437_pending(pending)
  end

  def to_terminal(data, :cp437) when is_binary(data) do
    transcode_cp437(data, [])
  end

  @doc "Converts a UTF-8 door output chunk with a pending partial sequence buffer."
  @spec to_terminal(binary(), :utf8, binary()) :: {binary(), binary()}
  def to_terminal(data, :utf8, pending) when is_binary(data) and is_binary(pending) do
    repair_utf8(pending <> data, [])
  end

  defp repair_utf8(<<>>, acc), do: {acc |> Enum.reverse() |> IO.iodata_to_binary(), ""}

  defp repair_utf8(<<codepoint::utf8, rest::binary>>, acc) do
    repair_utf8(rest, [<<codepoint::utf8>> | acc])
  end

  # Usurper Reborn emits mostly UTF-8, but some splash-art cells can arrive as
  # raw CP437 high bytes from legacy art assets. Buffer incomplete UTF-8 that was
  # split across PTY frames; convert only definitely invalid bytes to CP437.
  defp repair_utf8(<<byte, rest::binary>> = data, acc) do
    if incomplete_utf8_prefix?(byte, rest) do
      {acc |> Enum.reverse() |> IO.iodata_to_binary(), data}
    else
      repair_utf8(rest, [cp437_byte(byte) | acc])
    end
  end

  defp transcode_cp437(<<>>, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  # Preserve C0 controls, DEL, and printable ASCII bytes exactly. This keeps
  # CR/LF, ESC/CSI/OSC, tabs, and ordinary ANSI sequences functional while only
  # translating the high CP437 art/text bytes to UTF-8.
  defp transcode_cp437(<<byte, rest::binary>>, acc) when byte < 0x80 do
    transcode_cp437(rest, [<<byte>> | acc])
  end

  defp transcode_cp437(<<byte, rest::binary>>, acc) do
    transcode_cp437(rest, [cp437_byte(byte) | acc])
  end

  defp incomplete_utf8_prefix?(byte, rest) when byte in 0xC2..0xDF, do: byte_size(rest) < 1
  defp incomplete_utf8_prefix?(byte, rest) when byte in 0xE0..0xEF, do: byte_size(rest) < 2
  defp incomplete_utf8_prefix?(byte, rest) when byte in 0xF0..0xF4, do: byte_size(rest) < 3
  defp incomplete_utf8_prefix?(_byte, _rest), do: false

  defp cp437_pending(<<>>), do: ""
  defp cp437_pending(pending), do: transcode_cp437(pending, [])

  defp cp437_byte(byte) when byte < 0x80, do: <<byte>>
  defp cp437_byte(byte), do: Map.fetch!(@cp437, byte)
end
