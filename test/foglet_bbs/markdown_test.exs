defmodule Foglet.MarkdownTest do
  use ExUnit.Case, async: true

  alias Foglet.Markdown

  # MDEx is a Rust NIF loaded when the OTP application starts.
  # The test suite starts all apps via test_helper.exs — no special setup needed.

  # ---------------------------------------------------------------------------
  # New tuple-list contract (Gap 5) — render/1 returns [{String.t(), style_atom}]
  # ---------------------------------------------------------------------------

  describe "render/1 — bold (Gap 5)" do
    test "Test 1: renders **hello** as [{\"hello\", :bold}]" do
      result = Markdown.render("**hello**")
      assert {"hello", :bold} in result
      # Only bold tuples for this input (plus optional newline)
      non_newline = Enum.reject(result, fn {s, _} -> s == "\n" end)
      assert non_newline == [{"hello", :bold}]
    end

    test "renders __bold__ alternative syntax" do
      result = Markdown.render("__bold__")
      assert {"bold", :bold} in result
    end
  end

  describe "render/1 — italic (Gap 5)" do
    test "Test 2: renders *hi* as [{\"hi\", :italic}]" do
      result = Markdown.render("*hi*")
      assert {"hi", :italic} in result
      non_newline = Enum.reject(result, fn {s, _} -> s == "\n" end)
      assert non_newline == [{"hi", :italic}]
    end

    test "renders _italic_ alternative syntax" do
      result = Markdown.render("_italic_")
      assert {"italic", :italic} in result
    end
  end

  describe "render/1 — inline code (Gap 5)" do
    test "Test 3: renders `code` as [{\"code\", :dim}]" do
      result = Markdown.render("`code`")
      assert {"code", :dim} in result
      non_newline = Enum.reject(result, fn {s, _} -> s == "\n" end)
      assert non_newline == [{"code", :dim}]
    end
  end

  describe "render/1 — headings (Gap 5)" do
    test ~s(Test 4: renders # Title as [{"TITLE", :underline}, {"\\n", :plain}]) do
      result = Markdown.render("# Title")
      assert {"TITLE", :underline} in result
      assert {"\n", :plain} in result
    end

    test "renders ## heading with :underline and uppercased text" do
      result = Markdown.render("## Section")
      assert {"SECTION", :underline} in result
    end

    test "renders h3 through h6 headings with underline" do
      for level <- 3..6 do
        hashes = String.duplicate("#", level)
        result = Markdown.render("#{hashes} Sub")

        assert Enum.any?(result, fn {s, style} ->
                 String.upcase(s) == s and style == :underline
               end),
               "Expected heading level #{level} to render with underline"
      end
    end
  end

  describe "render/1 — plain text (Gap 5)" do
    test "Test 5: renders plain text with :plain style" do
      result = Markdown.render("plain")
      non_newline = Enum.reject(result, fn {s, _} -> s == "\n" end)
      assert non_newline == [{"plain", :plain}]
    end

    test "empty string returns empty list" do
      result = Markdown.render("")
      assert result == []
    end
  end

  describe "render/1 — mixed content (Gap 5)" do
    test "Test 6: renders **a** b as bold a followed by plain ' b'" do
      result = Markdown.render("**a** b")
      assert {"a", :bold} in result

      assert Enum.any?(result, fn {s, style} ->
               String.starts_with?(s, " b") and style == :plain
             end)
    end
  end

  describe "render/1 — ANSI injection defense (T-2-03)" do
    test "Test 7: raw ANSI injection yields only :plain styled tuples" do
      result = Markdown.render("\e[1mx\e[0m")
      # No :bold should appear from injected ESC sequences
      assert Enum.all?(result, fn {_s, style} -> style == :plain end),
             "Expected all tuples to be :plain when ANSI is injected, got: #{inspect(result)}"
    end

    test "raw ESC sequences in user input are stripped from output" do
      malicious_input = "hello \e[31mworld\e[0m"
      result = Markdown.render(malicious_input)

      all_text = Enum.map_join(result, "", fn {s, _} -> s end)

      refute String.contains?(all_text, "\e"),
             "User-injected ANSI ESC bytes should be stripped from output"

      assert Enum.any?(result, fn {s, _} -> String.contains?(s, "hello") end)
      assert Enum.any?(result, fn {s, _} -> String.contains?(s, "world") end)
    end

    test "multiple injected sequences are all stripped" do
      malicious = "\e[1mfake bold\e[0m and \e[31;1mfake red bold\e[0m"
      result = Markdown.render(malicious)

      all_text = Enum.map_join(result, "", fn {s, _} -> s end)
      refute String.contains?(all_text, "\e")
      assert String.contains?(all_text, "fake bold")
      assert String.contains?(all_text, "fake red bold")
    end

    test "OSC payloads and BEL controls are stripped from output" do
      malicious = "hello \e]52;c;clipboard\a world\abel"
      result = Markdown.render(malicious)

      all_text = Enum.map_join(result, "", fn {s, _} -> s end)
      refute String.contains?(all_text, "\e")
      refute String.contains?(all_text, "\a")
      refute String.contains?(all_text, "clipboard")
      assert String.contains?(all_text, "hello")
      assert String.contains?(all_text, "worldbel")
    end

    test "legitimate markdown bold still works after stripping" do
      result = Markdown.render("**real bold**")
      assert {"real bold", :bold} in result
    end
  end

  describe "render/1 — links (Gap 5)" do
    test "renders [text](url) as plain 'text (url)' tuple" do
      result = Markdown.render("[Click here](https://example.com)")
      all_text = Enum.map_join(result, "", fn {s, _} -> s end)
      assert String.contains?(all_text, "Click here (https://example.com)")
    end

    test "link text is preserved, href shown in parens" do
      result = Markdown.render("[Foglet BBS](https://foglet.io)")
      all_text = Enum.map_join(result, "", fn {s, _} -> s end)
      assert String.contains?(all_text, "Foglet BBS (https://foglet.io)")
    end
  end

  describe "render/1 — images (Gap 5)" do
    test "renders ![alt](url) as alt text only in plain tuple" do
      result = Markdown.render("![A cute cat](https://example.com/cat.jpg)")
      all_text = Enum.map_join(result, "", fn {s, _} -> s end)
      assert String.contains?(all_text, "A cute cat")
      refute String.contains?(all_text, "https://example.com/cat.jpg")
    end
  end

  describe "render/1 — code blocks (Gap 5)" do
    test "renders fenced code block with :dim tuples and 2-space indent" do
      markdown = """
      ```
      def hello do
        :world
      end
      ```
      """

      result = Markdown.render(markdown)
      # Should have at least one :dim tuple with indented content
      assert Enum.any?(result, fn {s, style} ->
               style == :dim and String.starts_with?(s, "  ")
             end)
    end

    test "code block does not render markdown syntax as :bold" do
      markdown = """
      ```
      **not bold**
      ```
      """

      result = Markdown.render(markdown)
      refute {"not bold", :bold} in result
      all_text = Enum.map_join(result, "", fn {s, _} -> s end)
      assert String.contains?(all_text, "not bold")
    end
  end

  describe "render/1 — combined (Gap 5)" do
    test "returns a list of {string, style} tuples for valid Markdown" do
      result = Markdown.render("**hello** *world*")
      assert is_list(result)
      assert Enum.all?(result, fn item -> match?({s, _a} when is_binary(s), item) end)
      assert {"hello", :bold} in result
      assert {"world", :italic} in result
    end

    test "paragraphs include newline tuples" do
      result = Markdown.render("First paragraph.\n\nSecond paragraph.")
      all_text = Enum.map_join(result, "", fn {s, _} -> s end)
      assert String.contains?(all_text, "First paragraph.")
      assert String.contains?(all_text, "Second paragraph.")
    end

    test "paragraph separators preserve consecutive newline tuples" do
      result = Markdown.render("First paragraph.\n\nSecond paragraph.")

      assert [
               {"First paragraph.", :plain},
               {"\n", :plain},
               {"\n", :plain},
               {"Second paragraph.", :plain},
               {"\n", :plain}
             ] = result
    end

    test "HTML entities in output are decoded" do
      result = Markdown.render("Cats & dogs")
      all_text = Enum.map_join(result, "", fn {s, _} -> s end)
      assert String.contains?(all_text, "Cats & dogs")
      refute String.contains?(all_text, "&amp;")
    end
  end
end
