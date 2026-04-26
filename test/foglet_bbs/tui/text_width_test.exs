defmodule Foglet.TUI.TextWidthTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.TextWidth

  describe "display_width/1" do
    test "measures ASCII text in terminal columns" do
      assert TextWidth.display_width("abc") == 3
    end

    test "delegates milestone glyph widths to Raxol" do
      for glyph <- ["●", "◆", "▸", "▾", "✓", "×"] do
        assert TextWidth.display_width(glyph) == Raxol.UI.TextMeasure.display_width(glyph)
      end
    end
  end

  describe "split_at/2" do
    test "splits ASCII text at display width" do
      assert TextWidth.split_at("abcdef", 3) == {"abc", "def"}
    end

    test "does not split accented Latin grapheme clusters" do
      assert TextWidth.split_at("café", 4) == {"café", ""}
      assert TextWidth.split_at("cafe\u0301", 4) == {"cafe\u0301", ""}
    end

    test "does not emit half CJK characters" do
      assert TextWidth.split_at("漢字", 1) == {"", "漢字"}
      assert TextWidth.split_at("漢字", 2) == {"漢", "字"}
    end
  end

  describe "slice_to_width/2" do
    test "returns the left side of a display-width split" do
      assert TextWidth.slice_to_width("abcdef", 4) == "abcd"
    end

    test "keeps combining marks with their base grapheme" do
      assert TextWidth.slice_to_width("cafe\u0301 noir", 4) == "cafe\u0301"
    end

    test "does not include CJK characters that exceed the requested width" do
      assert TextWidth.slice_to_width("漢字abc", 3) == "漢"
    end
  end

  describe "truncate/2 and truncate/3" do
    test "returns fitting ASCII text unchanged" do
      assert TextWidth.truncate("abc", 3) == "abc"
    end

    test "truncates overflowing ASCII text with the default ellipsis" do
      assert TextWidth.truncate("abcdef", 4) == "abc…"
    end

    test "supports a custom ellipsis option" do
      assert TextWidth.truncate("abcdef", 5, ellipsis: "..") == "abc.."
    end

    test "does not split combining marks while truncating" do
      assert TextWidth.truncate("cafe\u0301 noir", 5) == "cafe\u0301…"
    end

    test "does not split CJK characters while truncating" do
      assert TextWidth.truncate("漢字abc", 4) == "漢…"
    end

    test "returns an empty string for non-positive max width" do
      assert TextWidth.truncate("abc", 0) == ""
      assert TextWidth.truncate("abc", -1) == ""
    end
  end

  describe "wrap/2" do
    test "wraps ASCII words without exceeding display width" do
      lines = TextWidth.wrap("alpha beta gamma", 10)

      assert lines == ["alpha beta", "gamma"]
      assert Enum.all?(lines, &(TextWidth.display_width(&1) <= 10))
    end

    test "preserves newline boundaries and blank input lines" do
      assert TextWidth.wrap("first\n\nsecond", 8) == ["first", "", "second"]
    end

    test "wraps CJK graphemes without emitting oversized lines" do
      lines = TextWidth.wrap("あああああ", 2)

      assert length(lines) > 1
      assert Enum.join(lines) == "あああああ"
      assert Enum.all?(lines, &(TextWidth.display_width(&1) <= 2))
    end

    test "keeps combining marks with their base grapheme" do
      lines = TextWidth.wrap("cafe\u0301 noir", 5)

      assert lines == ["cafe\u0301", "noir"]
      assert Enum.all?(lines, &(TextWidth.display_width(&1) <= 5))
    end

    test "keeps ZWJ emoji grapheme clusters intact" do
      emoji = "👩‍💻"
      lines = TextWidth.wrap("#{emoji}#{emoji}#{emoji}", 4)

      assert length(lines) > 1
      assert Enum.join(lines) == "#{emoji}#{emoji}#{emoji}"
      assert Enum.all?(lines, &(TextWidth.display_width(&1) <= 4))
      assert Enum.all?(lines, fn line -> Enum.all?(String.graphemes(line), &(&1 == emoji)) end)
    end

    test "splits no-space ssh-rsa shaped blobs only when necessary" do
      blob = "ssh-rsa-AAAAB3NzaC1yc2EAAAADAQABAAABAQC"
      lines = TextWidth.wrap(blob, 12)

      assert length(lines) > 1
      assert Enum.join(lines) == blob
      assert Enum.all?(lines, &(TextWidth.display_width(&1) <= 12))
    end

    test "returns no lines for empty text or non-positive widths" do
      assert TextWidth.wrap("", 8) == []
      assert TextWidth.wrap("alpha", 0) == []
      assert TextWidth.wrap("alpha", -1) == []
    end
  end

  describe "pad_trailing/2 and pad_leading/2" do
    test "pads ASCII text to the requested display width" do
      assert TextWidth.pad_trailing("abc", 5) == "abc  "
      assert TextWidth.pad_leading("abc", 5) == "  abc"
    end

    test "preserves existing text when it already meets or exceeds the width" do
      assert TextWidth.pad_trailing("abcdef", 3) == "abcdef"
      assert TextWidth.pad_leading("abcdef", 3) == "abcdef"
    end

    test "pads using terminal display width for accented Latin and CJK" do
      assert TextWidth.pad_trailing("café", 6) == "café  "
      assert TextWidth.pad_leading("cafe\u0301", 6) == "  cafe\u0301"
      assert TextWidth.pad_trailing("漢字", 6) == "漢字  "
      assert TextWidth.pad_leading("漢字", 6) == "  漢字"
    end
  end
end
