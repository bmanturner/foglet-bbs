defmodule Foglet.TUI.Widgets.Post.PostCardTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Post.PostCard

  # Local helpers — same approach as MarkdownBodyTest.
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

  defp sample_post(overrides \\ %{}) do
    Map.merge(
      %{
        id: "post-abc",
        body: "Hello **bold** world.",
        inserted_at: DateTime.add(DateTime.utc_now(), -2 * 60 * 60, :second),
        user: %{handle: "sysop"}
      },
      overrides
    )
  end

  describe "render/4 — header content" do
    test "includes 'Post X of N' in dim text" do
      post = sample_post()
      result = PostCard.render(post, 80, theme(), index: 0, total: 3)
      flat = flatten_text(result)
      assert flat =~ "Post 1 of 3"
    end

    test "defaults to 'Post 1 of 1' when opts omitted" do
      result = PostCard.render(sample_post(), 80, theme())
      assert flatten_text(result) =~ "Post 1 of 1"
    end

    test "includes handle with @ prefix" do
      post = sample_post(%{user: %{handle: "brendan"}})
      result = PostCard.render(post, 80, theme())
      assert flatten_text(result) =~ "@brendan"
    end

    test "includes a short-form time-ago ('2h ago' for a 2-hour-old post)" do
      post = sample_post()
      result = PostCard.render(post, 80, theme())
      assert flatten_text(result) =~ "2h ago"
    end

    test "degrades gracefully when user is missing" do
      post = sample_post(%{user: nil})
      result = PostCard.render(post, 80, theme())
      refute is_nil(result)
      # Should still render the time-ago part
      assert flatten_text(result) =~ "ago"
    end

    test "degrades gracefully when inserted_at is missing" do
      post = sample_post(%{inserted_at: nil})
      result = PostCard.render(post, 80, theme())
      refute is_nil(result)
      assert flatten_text(result) =~ "@sysop"
    end

    test "accepts NaiveDateTime for inserted_at" do
      naive = NaiveDateTime.add(NaiveDateTime.utc_now(), -5 * 60, :second)
      post = sample_post(%{inserted_at: naive})
      result = PostCard.render(post, 80, theme())
      assert flatten_text(result) =~ "5m ago"
    end
  end

  describe "render/4 — body delegation" do
    test "renders body markdown through MarkdownBody (no literal \\n in output)" do
      post = sample_post(%{body: "First paragraph.\n\nSecond paragraph."})
      result = PostCard.render(post, 80, theme())
      flat = flatten_text(result)
      assert flat =~ "First paragraph."
      assert flat =~ "Second paragraph."
      refute String.contains?(flat, "First paragraph.\nSecond paragraph.")
    end

    test "nil body renders a card with empty body (no crash)" do
      post = sample_post(%{body: nil})
      result = PostCard.render(post, 80, theme())
      refute is_nil(result)
      # Header still renders
      assert flatten_text(result) =~ "Post 1 of 1"
    end

    test "bold body text is themed with accent color" do
      t = theme()
      post = sample_post(%{body: "plain **bold**"})
      result = PostCard.render(post, 80, t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      assert serialized =~ t.accent.fg
    end

    test "scroll_offset is forwarded to MarkdownBody" do
      post = sample_post(%{body: "line A\n\nline B\n\nline C"})
      # With scroll_offset 2, only line C should remain in body text
      result = PostCard.render(post, 80, theme(), scroll_offset: 2, max_lines: :all)
      flat = flatten_text(result)
      refute flat =~ "line A"
      refute flat =~ "line B"
      assert flat =~ "line C"
    end

    test "max_lines is forwarded to MarkdownBody" do
      post = sample_post(%{body: "line A\n\nline B\n\nline C"})
      result = PostCard.render(post, 80, theme(), scroll_offset: 0, max_lines: 1)
      flat = flatten_text(result)
      assert flat =~ "line A"
      refute flat =~ "line C"
    end
  end

  describe "render_from_tuples/5" do
    test "produces the same body as render/4 when given equivalent tuples" do
      post = sample_post(%{body: "hello **world**"})
      tuples = Foglet.Markdown.render("hello **world**")

      a = PostCard.render(post, 80, theme())
      b = PostCard.render_from_tuples(post, tuples, 80, theme())

      assert flatten_text(a) == flatten_text(b)
    end
  end

  describe "body_line_count/1" do
    test "returns 0 for nil" do
      assert PostCard.body_line_count(nil) == 0
    end

    test "matches MarkdownBody.line_count for a string" do
      body = "first\n\nsecond\n\nthird"

      assert PostCard.body_line_count(body) ==
               Foglet.TUI.Widgets.Post.MarkdownBody.line_count(body)
    end
  end

  describe "render_body_lines/4 — flat list for Viewport children" do
    test "returns a list (not a column element)" do
      tuples = Foglet.Markdown.render("Hello.\n\nWorld.")
      result = PostCard.render_body_lines(tuples, 80, theme())
      assert is_list(result)
      refute is_map(result)
    end

    test "each element is a Raxol view element map" do
      tuples = Foglet.Markdown.render("Line one.\n\nLine two.")
      result = PostCard.render_body_lines(tuples, 80, theme())
      assert Enum.all?(result, &is_map/1)
      assert Enum.all?(result, fn el -> Map.has_key?(el, :type) or Map.has_key?(el, :content) end)
    end

    test "list length matches MarkdownBody.line_count for the same body" do
      body = "A\n\nB\n\nC"
      tuples = Foglet.Markdown.render(body)
      result = PostCard.render_body_lines(tuples, 80, theme())
      assert length(result) == Foglet.TUI.Widgets.Post.MarkdownBody.line_count(body)
      assert length(result) == 3
    end

    test "body content is included but header content is NOT" do
      body = "Hello **world**."
      tuples = Foglet.Markdown.render(body)
      result = PostCard.render_body_lines(tuples, 80, theme(), index: 0, total: 5)
      flat = flatten_text(result)
      assert flat =~ "world", "body text should be present, flat=#{inspect(flat)}"
      refute flat =~ "Post 1 of 5", "header 'Post X of N' must NOT be present"
      refute flat =~ "By @", "author line must NOT be present"
      refute flat =~ "sysop", "handle must NOT be present"
    end

    test "opts (scroll_offset, max_lines) are ignored — no windowing" do
      body = "A\n\nB\n\nC\n\nD"
      tuples = Foglet.Markdown.render(body)
      full = PostCard.render_body_lines(tuples, 80, theme())

      windowed =
        PostCard.render_body_lines(tuples, 80, theme(),
          scroll_offset: 99,
          max_lines: 1
        )

      assert length(full) == length(windowed)
    end
  end

  describe "render/4 — theme hygiene" do
    test "no hardcoded color atoms appear anywhere in the tree" do
      post = sample_post(%{body: "A **bold** post with `code` and *italics*."})
      result = PostCard.render(post, 80, theme())
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      refute serialized =~ ":green"
      refute serialized =~ ":cyan"
      refute serialized =~ ":red"
      refute serialized =~ ":yellow"
    end

    test "header uses theme.dim.fg" do
      t = theme()
      post = sample_post()
      result = PostCard.render(post, 80, t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      assert serialized =~ t.dim.fg
    end

    test "header divider uses theme.border.fg" do
      t = theme()
      post = sample_post()
      result = PostCard.render(post, 80, t)
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)
      assert serialized =~ t.border.fg
    end
  end
end
