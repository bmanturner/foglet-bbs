defmodule Foglet.MarkdownTest do
  use ExUnit.Case, async: true

  alias Foglet.Markdown

  # MDEx is a Rust NIF loaded when the OTP application starts.
  # The test suite starts all apps via test_helper.exs — no special setup needed.

  describe "render/1 — bold (BOARD-05)" do
    test "renders **bold** with ANSI bold escape \\e[1m...\\e[0m" do
      result = Markdown.render("**hello world**")
      assert result =~ "\e[1mhello world\e[0m"
    end

    test "renders __bold__ alternative syntax" do
      result = Markdown.render("__bold__")
      assert result =~ "\e[1mbold\e[0m"
    end
  end

  describe "render/1 — italic (BOARD-05)" do
    test "renders *italic* with ANSI italic escape \\e[3m...\\e[0m" do
      result = Markdown.render("*italic text*")
      assert result =~ "\e[3mitalic text\e[0m"
    end

    test "renders _italic_ alternative syntax" do
      result = Markdown.render("_italic_")
      assert result =~ "\e[3mitalic\e[0m"
    end
  end

  describe "render/1 — headings (BOARD-05)" do
    test "renders # heading with ANSI underline \\e[4m and uppercased text" do
      result = Markdown.render("# Hello World")
      assert result =~ "\e[4mHELLO WORLD\e[0m"
    end

    test "renders ## heading with ANSI underline" do
      result = Markdown.render("## Section")
      assert result =~ "\e[4mSECTION\e[0m"
    end

    test "renders h3 through h6 headings with underline" do
      for level <- 3..6 do
        hashes = String.duplicate("#", level)
        result = Markdown.render("#{hashes} Sub")

        assert result =~ "\e[4mSUB\e[0m",
               "Expected heading level #{level} to render with underline"
      end
    end
  end

  describe "render/1 — inline code (BOARD-05)" do
    test "renders `code` with ANSI dim escape \\e[2m...\\e[0m" do
      result = Markdown.render("`my_function/1`")
      assert result =~ "\e[2mmy_function/1\e[0m"
    end
  end

  describe "render/1 — code blocks (BOARD-05)" do
    test "renders fenced code block with dim color and 2-space indent" do
      markdown = """
      ```
      def hello do
        :world
      end
      ```
      """

      result = Markdown.render(markdown)
      # Each line should have 2-space indent and dim color
      assert result =~ "  \e[2m"
      assert result =~ "\e[0m"
    end

    test "code block does not render markdown syntax as formatting" do
      markdown = """
      ```
      **not bold**
      ```
      """

      result = Markdown.render(markdown)
      # ** should appear as literal text inside dim block, not as bold ANSI
      refute result =~ "\e[1mnot bold\e[0m"
      assert result =~ "not bold"
    end
  end

  describe "render/1 — links (BOARD-05)" do
    test "renders [text](url) as 'text (url)' — no HTML href tags in output" do
      result = Markdown.render("[Click here](https://example.com)")
      assert result =~ "Click here (https://example.com)"
      refute result =~ "<a "
      refute result =~ "href="
    end

    test "link text is preserved, href shown in parens" do
      result = Markdown.render("[Foglet BBS](https://foglet.io)")
      assert result =~ "Foglet BBS (https://foglet.io)"
    end
  end

  describe "render/1 — images (BOARD-05)" do
    test "renders ![alt](url) as alt text only — no HTML img tags in output" do
      result = Markdown.render("![A cute cat](https://example.com/cat.jpg)")
      assert result =~ "A cute cat"
      refute result =~ "https://example.com/cat.jpg"
      refute result =~ "<img"
    end

    test "image with empty alt renders nothing visible" do
      result = Markdown.render("![](https://example.com/img.png)")
      refute result =~ "https://example.com/img.png"
      refute result =~ "<img"
    end
  end

  describe "render/1 — ANSI injection defense (T-2-03)" do
    test "raw ESC sequences in user input are stripped from output" do
      # User tries to inject a red color sequence through their post body
      malicious_input = "hello \e[31mworld\e[0m"
      result = Markdown.render(malicious_input)

      # The injected \e[31m must NOT appear in the output
      refute result =~ "\e[31m",
             "User-injected ANSI red color should be stripped from output"

      # But the text itself should still be present
      assert result =~ "hello"
      assert result =~ "world"
    end

    test "ESC character alone is stripped" do
      result = Markdown.render("hello\e world")
      refute result =~ "\e"
      assert result =~ "hello"
    end

    test "multiple injected sequences are all stripped" do
      malicious = "\e[1mfake bold\e[0m and \e[31;1mfake red bold\e[0m"
      result = Markdown.render(malicious)
      refute result =~ "\e[1mfake bold"
      refute result =~ "\e[31"
      assert result =~ "fake bold"
      assert result =~ "fake red bold"
    end

    test "legitimate markdown bold still works after stripping" do
      # Ensure strip_ansi doesn't break real markdown formatting
      result = Markdown.render("**real bold**")
      assert result =~ "\e[1mreal bold\e[0m"
    end
  end

  describe "render/1 — combined and edge cases (BOARD-05)" do
    test "returns a string (ANSI-escaped plain text) for valid Markdown" do
      result = Markdown.render("**hello** *world*")
      assert is_binary(result)
      assert result =~ "\e[1mhello\e[0m"
      assert result =~ "\e[3mworld\e[0m"
    end

    test "returns plain text when input has no Markdown formatting" do
      result = Markdown.render("Just plain text.")
      assert String.contains?(result, "Just plain text.")
    end

    test "empty string returns empty string" do
      result = Markdown.render("")
      assert result == ""
    end

    test "nested bold and italic" do
      result = Markdown.render("***bold italic***")
      # MDEx renders ***text*** as <em><strong>text</strong></em>
      # Both bold and italic ANSI codes should appear
      assert result =~ "\e[1m"
      assert result =~ "\e[3m"
    end

    test "paragraphs are separated by newlines" do
      result = Markdown.render("First paragraph.\n\nSecond paragraph.")
      assert result =~ "First paragraph."
      assert result =~ "Second paragraph."
    end

    test "HTML entities in output are decoded" do
      # Ampersand in markdown should appear as & not &amp;
      result = Markdown.render("Cats & dogs")
      assert result =~ "Cats & dogs"
      refute result =~ "&amp;"
    end
  end
end
