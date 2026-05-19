defmodule Foglet.Doors.OutputEncodingTest do
  use ExUnit.Case, async: true

  alias Foglet.Doors.OutputEncoding

  describe "to_terminal/2" do
    test "leaves UTF-8 door output unchanged" do
      assert OutputEncoding.to_terminal("Welcome, Foglet!\r\n", :utf8) == "Welcome, Foglet!\r\n"
    end

    test "transcodes CP437 splash art bytes to UTF-8 while preserving ANSI/control bytes" do
      cp437 =
        <<0x1B, ?[, ?3, ?1, ?m, 0xDA, 0xC4, 0xBF, ?\r, ?\n, 0xB3, ?U, ?s, ?u, ?r, ?p, ?e, ?r,
          0xB3>>

      assert OutputEncoding.to_terminal(cp437, :cp437) == "\e[31m┌─┐\r\n│Usurper│"
    end

    test "does not emit replacement-character mojibake for high CP437 bytes" do
      text = OutputEncoding.to_terminal(<<0xDB, 0xB1, 0xB2, 0xFE>>, :cp437)

      refute text =~ "�"
      assert text == "█▒▓■"
    end

    test "repairs isolated invalid CP437 bytes in otherwise UTF-8 output" do
      text =
        OutputEncoding.to_terminal(
          "████▀" <> <<0xDC, 0xDC>> <> "▀▀▀█▄\r\nPress any key...",
          :utf8
        )

      refute text =~ "�"
      assert text == "████▀▄▄▀▀▀█▄\r\nPress any key..."
    end

    test "buffers UTF-8 characters split across output chunks" do
      <<first::binary-size(1), rest::binary>> = "■"

      assert {"", first} == OutputEncoding.to_terminal(first, :utf8, "")
      assert {"■", ""} == OutputEncoding.to_terminal(rest, :utf8, first)
    end
  end
end
