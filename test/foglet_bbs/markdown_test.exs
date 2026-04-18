defmodule Foglet.MarkdownTest do
  use ExUnit.Case, async: true

  describe "Foglet.Markdown.render/1 (BOARD-05)" do
    @tag :pending
    test "returns a string (ANSI-escaped plain text) for valid Markdown" do
      flunk("Pending — Plan 04 implements Foglet.Markdown.render/1")
    end

    @tag :pending
    test "renders bold text with ANSI bold escape \\e[1m...\\e[0m" do
      flunk("Pending — Plan 04 implements D-02 ANSI mapping: bold → \\e[1m")
    end

    @tag :pending
    test "renders italic text with ANSI italic escape \\e[3m...\\e[0m" do
      flunk("Pending — Plan 04 implements D-02 ANSI mapping: italic → \\e[3m")
    end

    @tag :pending
    test "renders headings as uppercase text with underline escape \\e[4m" do
      flunk("Pending — Plan 04 implements D-02 ANSI mapping: headings → uppercase + underline")
    end

    @tag :pending
    test "renders code spans with dim escape \\e[2m...\\e[0m" do
      flunk("Pending — Plan 04 implements D-02 ANSI mapping: code spans → dim")
    end

    @tag :pending
    test "renders links as display text (url) — no HTML href tags in output" do
      flunk("Pending — Plan 04 implements D-02 ANSI mapping: links → text (url)")
    end

    @tag :pending
    test "renders image alt text only — no HTML img tags in output" do
      flunk("Pending — Plan 04 implements D-02 ANSI mapping: images → alt text")
    end

    @tag :pending
    test "returns plain text when input has no Markdown formatting" do
      flunk("Pending — Plan 04 implements passthrough for plain text")
    end
  end
end
