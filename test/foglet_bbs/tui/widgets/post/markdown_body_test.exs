defmodule Foglet.TUI.Widgets.Post.MarkdownBodyTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Post.MarkdownBody

  # Walk the view tree and flatten every leaf text content into a
  # single string. Handles both element structs (Raxol 2.4.0) and
  # tagged-map fallbacks.
  defp flatten_text(tree), do: tree |> collect_text([]) |> Enum.reverse() |> Enum.join("")

  defp collect_text(nil, acc), do: acc
  defp collect_text(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect_text/2)

  defp collect_text(%{children: children} = node, acc) do
    acc = maybe_add_content(node, acc)
    collect_text(children, acc)
  end

  defp collect_text(%{content: content}, acc) when is_binary(content), do: [content | acc]
  defp collect_text(%{text: t}, acc) when is_binary(t), do: [t | acc]
  defp collect_text(_other, acc), do: acc

  defp maybe_add_content(%{content: content}, acc) when is_binary(content), do: [content | acc]
  defp maybe_add_content(_node, acc), do: acc

  # Count the number of children inside the top-level column.
  # Works for both element-struct and tagged-map shapes.
  defp top_level_line_count(%{children: children}) when is_list(children), do: length(children)

  defp top_level_line_count(%{children: child}) when not is_list(child), do: 1

  defp top_level_line_count(tree) when is_list(tree), do: length(tree)

  defp top_level_line_count(_), do: 0

  defp theme, do: Theme.default()

  describe "render/4 — basic contract" do
    test "returns a view element for empty input" do
      result = MarkdownBody.render("", 80, theme())
      refute is_nil(result)
    end

    test "returns a view element for a single paragraph" do
      result = MarkdownBody.render("Hello world.", 80, theme())
      refute is_nil(result)
      assert flatten_text(result) =~ "Hello world."
    end

    test "does not emit literal \\n characters in rendered content" do
      result = MarkdownBody.render("First paragraph.\n\nSecond paragraph.", 80, theme())
      flat = flatten_text(result)
      assert flat =~ "First paragraph."
      assert flat =~ "Second paragraph."

      # RENDER-01 root-cause: no visible "\n" should appear as text content
      # in any leaf of the rendered tree. `flatten_text/1` concatenates leaf
      # content strings; if `{"\n", :plain}` tuples leaked into `text/2`
      # nodes, the character "\n" would appear in `flat`.
      refute String.contains?(flat, "\n"),
             "Expected no literal '\\n' characters in rendered output, got: #{inspect(flat)}"
    end
  end

  describe "render/4 — line grouping (RENDER-01)" do
    test "two-paragraph input produces exactly 2 line groups" do
      result = MarkdownBody.render("First.\n\nSecond.", 80, theme())
      assert top_level_line_count(result) == 2
    end

    test "heading followed by paragraph produces exactly 2 line groups" do
      result = MarkdownBody.render("# Title\n\nBody text.", 80, theme())
      assert top_level_line_count(result) == 2
    end

    test "bulleted list produces one line per bullet" do
      input = "- first\n- second\n- third"
      result = MarkdownBody.render(input, 80, theme())
      assert top_level_line_count(result) == 3
    end

    test "single paragraph with inline bold produces exactly 1 line group" do
      result = MarkdownBody.render("hello **world**", 80, theme())
      assert top_level_line_count(result) == 1
    end
  end

  describe "render/4 — theme application (D-06, RENDER-01)" do
    test "does not emit hardcoded :green atom anywhere in the tree" do
      # Assert the tree itself contains no `:green` color atom — we only
      # accept hex strings from the theme.
      result = MarkdownBody.render("**bold** and *italic* and `code`", 80, theme())
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      refute serialized =~ ":green"
      refute serialized =~ ":cyan"
      refute serialized =~ ":red"
      refute serialized =~ ":yellow"
    end

    test "bold run uses theme.accent.fg" do
      t = theme()
      result = MarkdownBody.render("**bold**", 80, t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)

      assert serialized =~ t.accent.fg,
             "Expected bold run to use theme.accent.fg (#{t.accent.fg}), tree: #{serialized}"
    end

    test "heading run uses theme.title.fg" do
      t = theme()
      result = MarkdownBody.render("# Heading", 80, t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)

      assert serialized =~ t.title.fg,
             "Expected heading to use theme.title.fg (#{t.title.fg}), tree: #{serialized}"
    end

    test "inline code uses theme.dim.fg" do
      t = theme()
      result = MarkdownBody.render("Run `mix test` first.", 80, t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)

      assert serialized =~ t.dim.fg,
             "Expected inline code to use theme.dim.fg (#{t.dim.fg}), tree: #{serialized}"
    end
  end

  describe "render/4 — scroll window" do
    test "scroll_offset: 0, max_lines: :all renders all lines" do
      input = "line 1\n\nline 2\n\nline 3"
      result = MarkdownBody.render(input, 80, theme(), scroll_offset: 0, max_lines: :all)
      assert top_level_line_count(result) == 3
    end

    test "scroll_offset: 1 drops the first line" do
      input = "line 1\n\nline 2\n\nline 3"
      result = MarkdownBody.render(input, 80, theme(), scroll_offset: 1, max_lines: :all)
      assert top_level_line_count(result) == 2
      flat = flatten_text(result)
      refute flat =~ "line 1"
      assert flat =~ "line 2"
      assert flat =~ "line 3"
    end

    test "max_lines: 1 renders only the first line" do
      input = "line 1\n\nline 2\n\nline 3"
      result = MarkdownBody.render(input, 80, theme(), scroll_offset: 0, max_lines: 1)
      assert top_level_line_count(result) == 1
      assert flatten_text(result) =~ "line 1"
    end

    test "scroll_offset past end yields a non-nil single-line result" do
      result =
        MarkdownBody.render("line 1\n\nline 2", 80, theme(),
          scroll_offset: 99,
          max_lines: 5
        )

      # Empty windowed result falls back to a single blank row
      refute is_nil(result)
    end
  end

  describe "line_count/1" do
    test "returns 0 for empty input" do
      assert MarkdownBody.line_count("") == 0
    end

    test "returns 1 for a single paragraph" do
      assert MarkdownBody.line_count("hello") == 1
    end

    test "counts each paragraph as one logical line" do
      assert MarkdownBody.line_count("first\n\nsecond") == 2
    end

    test "counts each bullet as one logical line" do
      assert MarkdownBody.line_count("- a\n- b\n- c") == 3
    end
  end

  describe "render_tuples/4 — direct entry point" do
    test "produces the same output as render/4 for a paragraph" do
      tuples = Foglet.Markdown.render("**hello**")
      t = theme()

      a = MarkdownBody.render("**hello**", 80, t)
      b = MarkdownBody.render_tuples(tuples, 80, t)

      assert flatten_text(a) == flatten_text(b)
      assert top_level_line_count(a) == top_level_line_count(b)
    end
  end
end
