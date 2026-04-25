defmodule Foglet.TUI.Widgets.List.ListRowTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Theme
  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Widgets.List.ListRow

  # --- Local helpers (copied from MarkdownBody/PostCard test pattern) ---

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

  defp theme, do: Theme.default()

  describe "render/3 — backwards compatibility (Phase 1 signature)" do
    test "unselected row emits marker + title" do
      result = ListRow.render("Hello", false, theme())
      flat = flatten_text(result)
      assert flat == "  Hello"
    end

    test "selected row emits '> ' marker + title" do
      result = ListRow.render("Hello", true, theme())
      flat = flatten_text(result)
      assert flat == "> Hello"
    end
  end

  describe "render_with_metadata/6 — layout (D-01, D-02, D-03)" do
    test "right-aligns metadata at the requested width" do
      result =
        ListRow.render_with_metadata(
          "Short title",
          "@alice · 2h ago",
          false,
          false,
          theme(),
          width: 60
        )

      flat = flatten_text(result)
      assert TextWidth.display_width(flat) == 60
      assert String.ends_with?(flat, "@alice · 2h ago")
      assert String.starts_with?(flat, "  Short title")
    end

    test "selected row starts with '> ' marker" do
      result =
        ListRow.render_with_metadata(
          "Short title",
          "@alice · 2h ago",
          true,
          false,
          theme(),
          width: 60
        )

      flat = flatten_text(result)
      assert String.starts_with?(flat, "> Short title")
    end

    test "truncates long title with … when combined width exceeds terminal (D-03)" do
      long_title =
        "This is a very very very long thread title that will definitely overflow the row width"

      metadata = "@alice · 5 posts · 2h ago"

      result =
        ListRow.render_with_metadata(
          long_title,
          metadata,
          false,
          false,
          theme(),
          width: 60
        )

      flat = flatten_text(result)
      assert TextWidth.display_width(flat) == 60
      assert String.ends_with?(flat, metadata), "metadata must stay fully visible (D-03)"
      assert String.contains?(flat, "…"), "title must be truncated with … (D-03)"
    end

    test "metadata is fully preserved even when title is extremely long" do
      long_title = String.duplicate("x", 500)
      metadata = "@a · 1h ago"

      result =
        ListRow.render_with_metadata(long_title, metadata, false, false, theme(), width: 40)

      flat = flatten_text(result)
      assert String.ends_with?(flat, metadata)
    end

    test "short title + short metadata fits with padding spaces between them" do
      result =
        ListRow.render_with_metadata(
          "A",
          "@b · 1h ago",
          false,
          false,
          theme(),
          width: 60
        )

      flat = flatten_text(result)
      assert TextWidth.display_width(flat) == 60
    end

    test "minimum gap of 2 spaces between title and metadata when width is tight" do
      title = String.duplicate("x", 25)
      metadata = "@a · 1h"

      result =
        ListRow.render_with_metadata(title, metadata, false, false, theme(), width: 31)

      flat = flatten_text(result)
      assert String.ends_with?(flat, metadata)
      assert TextWidth.display_width(flat) == 31
    end

    test "extremely narrow terminal keeps metadata whole (ellipsis fallback on title)" do
      title = "Extremely long title here"
      metadata = "@alice · 2h ago"

      result =
        ListRow.render_with_metadata(title, metadata, false, false, theme(), width: 25)

      flat = flatten_text(result)
      assert String.ends_with?(flat, metadata), "metadata must survive even at very narrow widths"

      before_metadata = String.replace_trailing(flat, metadata, "")
      assert String.contains?(before_metadata, "…")
    end

    test "keeps accented Latin rows aligned by display width" do
      metadata = "@renee · café"

      result =
        ListRow.render_with_metadata(
          "café update",
          metadata,
          false,
          false,
          theme(),
          width: 42
        )

      flat = flatten_text(result)
      assert TextWidth.display_width(flat) == 42
      assert String.starts_with?(flat, "  café update")
      assert String.ends_with?(flat, metadata)
    end

    test "keeps combining mark rows aligned by display width" do
      metadata = "@zoe · ✓ done"

      result =
        ListRow.render_with_metadata(
          "cafe\u0301 update",
          metadata,
          false,
          false,
          theme(),
          width: 42
        )

      flat = flatten_text(result)
      assert TextWidth.display_width(flat) == 42
      assert String.starts_with?(flat, "  cafe\u0301 update")
      assert String.ends_with?(flat, metadata)
    end

    test "truncates CJK titles without drifting metadata alignment" do
      metadata = "@lin · ◆ pinned"

      result =
        ListRow.render_with_metadata(
          "漢字 board report with a very long title",
          metadata,
          false,
          false,
          theme(),
          width: 34
        )

      flat = flatten_text(result)
      assert TextWidth.display_width(flat) == 34
      assert String.ends_with?(flat, metadata)
      assert String.contains?(flat, "…")
    end

    test "keeps milestone glyph titles and metadata aligned" do
      metadata = "▸ nav ▾ open ✓ ok × err"

      result =
        ListRow.render_with_metadata(
          "● unread ◆ pinned update",
          metadata,
          false,
          false,
          theme(),
          width: 58
        )

      flat = flatten_text(result)
      assert TextWidth.display_width(flat) == 58
      assert String.starts_with?(flat, "  ● unread ◆ pinned update")
      assert String.ends_with?(flat, metadata)
    end
  end

  describe "render_with_metadata/6 — bold-on-unread styling (D-04)" do
    test "unselected + unread title uses theme.primary.fg with :bold style" do
      t = theme()

      result =
        ListRow.render_with_metadata(
          "Unread thread",
          "@a · 1h ago",
          false,
          true,
          t,
          width: 60
        )

      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)

      assert serialized =~ to_string(t.primary.fg)
      assert serialized =~ ":bold"
    end

    test "unselected + read title uses theme.unselected.fg (no :bold)" do
      t = theme()

      result =
        ListRow.render_with_metadata(
          "Read thread",
          "@a · 1h ago",
          false,
          false,
          t,
          width: 60
        )

      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)

      assert serialized =~ to_string(t.unselected.fg)
    end

    test "selected row ignores unread? flag (selection highlight wins)" do
      t = theme()

      result_unread =
        ListRow.render_with_metadata("T", "@a · 1h", true, true, t, width: 60)

      result_read =
        ListRow.render_with_metadata("T", "@a · 1h", true, false, t, width: 60)

      s1 = inspect(result_unread, printable_limit: :infinity, limit: :infinity)
      s2 = inspect(result_read, printable_limit: :infinity, limit: :infinity)

      assert s1 =~ to_string(t.selected.bg)
      assert s2 =~ to_string(t.selected.bg)
    end

    test "metadata uses theme.dim.fg for unselected rows (both read and unread)" do
      t = theme()

      read =
        ListRow.render_with_metadata("T", "@a · 1h", false, false, t, width: 60)

      unread =
        ListRow.render_with_metadata("T", "@a · 1h", false, true, t, width: 60)

      assert inspect(read, printable_limit: :infinity, limit: :infinity) =~ to_string(t.dim.fg)
      assert inspect(unread, printable_limit: :infinity, limit: :infinity) =~ to_string(t.dim.fg)
    end
  end

  describe "render_with_metadata/6 — theme hygiene" do
    test "no hardcoded color atoms appear in the output" do
      result =
        ListRow.render_with_metadata(
          "Title",
          "@a · 1h",
          false,
          true,
          theme(),
          width: 60
        )

      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      refute serialized =~ ":green"
      refute serialized =~ ":cyan"
      refute serialized =~ ":red"
      refute serialized =~ ":yellow"
    end

    test "default width (opts omitted) is 80" do
      result = ListRow.render_with_metadata("T", "@a · 1h", false, false, theme())
      flat = flatten_text(result)
      assert TextWidth.display_width(flat) == 80
    end
  end
end
