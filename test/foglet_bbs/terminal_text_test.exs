defmodule Foglet.TerminalTextTest do
  use ExUnit.Case, async: true

  alias Foglet.TerminalText

  describe "sanitize_plain_text/1" do
    test "removes CSI and OSC sequences while preserving printable text" do
      malicious = "hello \e[31mred\e[0m \e]52;c;Zm9v\a world"

      assert TerminalText.sanitize_plain_text(malicious) == "hello red  world"
    end

    test "removes OSC terminated by ST and raw BEL/control bytes" do
      malicious = "left\e]0;spoofed title\e\\right\achr\rnext"

      assert TerminalText.sanitize_plain_text(malicious) == "leftrightchrnext"
    end

    test "removes 8-bit C1 CSI and OSC controls from binaries" do
      malicious = "alpha" <> <<0x9B>> <> "31mred" <> <<0x9D>> <> "title" <> <<0x9C>> <> "omega"

      assert TerminalText.sanitize_plain_text(malicious) == "alpharedomega"
    end

    test "preserves newline and tab as layout whitespace" do
      assert TerminalText.sanitize_plain_text("one\n\ttwo") == "one\n\ttwo"
    end
  end
end
