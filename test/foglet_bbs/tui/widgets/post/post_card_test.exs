defmodule Foglet.TUI.Widgets.Post.PostCardTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers,
    only: [flatten_text: 1, color_atom_leaked?: 2, color_names: 0]

  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Post.PostCard

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

  defp reader_body_text(line) do
    line
    |> flatten_text()
    |> String.replace_prefix("│", "")
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
      # With paragraph blanks preserved, offset 4 reaches the third content line.
      result = PostCard.render(post, 80, theme(), scroll_offset: 4, max_lines: :all)
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

  describe "reader_parts/5" do
    test "returns compact header atoms for a normal post" do
      post =
        sample_post(%{
          message_number: 42,
          inserted_at: DateTime.add(DateTime.utc_now(), -5 * 60, :second),
          user: %{handle: "mina"}
        })

      parts =
        PostCard.reader_parts(post, Foglet.Markdown.render("Hello"), 80, theme(),
          index: 0,
          total: 1
        )

      header = flatten_text(parts.header)

      assert header =~ "Post 1 of 1"
      assert header =~ "#42"
      assert header =~ "@mina"
      assert header =~ "ago"
    end

    test "truncates long handles so reader header stays within width" do
      width = 40

      post =
        sample_post(%{
          message_number: 42,
          user: %{handle: String.duplicate("reader-handle-", 8)}
        })

      parts =
        PostCard.reader_parts(post, Foglet.Markdown.render("Hello"), width, theme(),
          index: 0,
          total: 1
        )

      assert TextWidth.display_width(flatten_text(parts.header)) <= width
    end

    test "falls back explicitly for missing reader metadata" do
      post = sample_post(%{message_number: nil, inserted_at: nil, user: nil})

      parts =
        PostCard.reader_parts(post, Foglet.Markdown.render("Hello"), 80, theme(),
          index: 0,
          total: 1
        )

      header = flatten_text(parts.header)

      assert header =~ "#?"
      assert header =~ "@unknown"
      assert header =~ "age ?"
    end

    test "routes header styling through theme slots without hardcoded color atoms" do
      t = theme()
      post = sample_post(%{message_number: 42, user: %{handle: "mina"}})

      parts =
        PostCard.reader_parts(post, Foglet.Markdown.render("Hello"), 80, t, index: 0, total: 1)

      serialized = inspect(parts.header, printable_limit: :infinity, limit: :infinity)

      assert serialized =~ t.dim.fg or serialized =~ t.title.fg or serialized =~ t.badge.fg or
               serialized =~ t.accent.fg

      for color <- color_names() do
        refute color_atom_leaked?(serialized, color), "reader header leaked :#{color}"
      end
    end

    test "returns compact progress outside body lines" do
      post = sample_post(%{message_number: 42})

      parts =
        PostCard.reader_parts(post, Foglet.Markdown.render("Hello"), 80, theme(),
          index: 2,
          total: 12
        )

      assert flatten_text(parts.progress) =~ "Posts 3/12"
      refute flatten_text(parts.body_lines) =~ "Posts 3/12"
    end

    test "truncates progress so it stays within narrow reader width" do
      width = 8
      post = sample_post(%{message_number: 42})

      parts =
        PostCard.reader_parts(post, Foglet.Markdown.render("Hello"), width, theme(),
          index: 123_455,
          total: 987_654
        )

      assert TextWidth.display_width(flatten_text(parts.progress)) <= width
    end

    test "returns guttered body lines as separate Raxol view elements" do
      post = sample_post(%{message_number: 42, user: %{handle: "mina"}})

      parts =
        PostCard.reader_parts(post, Foglet.Markdown.render("Hello reader"), 80, theme(),
          index: 0,
          total: 1
        )

      assert %{header: _header, progress: _progress, body_lines: [_ | _]} = parts
      assert is_list(parts.body_lines)
      assert Enum.all?(parts.body_lines, &is_map/1)
      assert flatten_text(parts.body_lines) =~ "│"
      assert flatten_text(parts.body_lines) =~ "Hello reader"
      refute flatten_text(parts.body_lines) =~ "Post 1 of"
      refute flatten_text(parts.body_lines) =~ "Posts 1/1"
    end

    test "guttered body preserves markdown styling output" do
      post = sample_post(%{message_number: 42})
      tuples = Foglet.Markdown.render("Hello **world**")

      parts = PostCard.reader_parts(post, tuples, 80, theme(), index: 0, total: 1)
      serialized = inspect(parts.body_lines, printable_limit: :infinity, limit: :infinity)

      refute serialized =~ "**world**"
      assert serialized =~ "world"
    end

    test "wraps long unbroken reader body text to the reduced body width" do
      width = 64
      gutter_width = TextWidth.display_width("│")
      body_width = width - gutter_width - 2
      long_body = String.duplicate("x", 100)
      post = sample_post(%{message_number: 42})
      tuples = Foglet.Markdown.render(long_body)

      parts = PostCard.reader_parts(post, tuples, width, theme(), index: 0, total: 1)

      assert length(parts.body_lines) > 1

      for body_line <- parts.body_lines do
        body_text = reader_body_text(body_line)

        assert TextWidth.display_width(body_text) <= body_width
        assert gutter_width + 1 + TextWidth.display_width(body_text) <= width
      end
    end

    test "wraps long reader paragraphs into multiple guttered viewport rows" do
      width = 40
      body = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu"
      post = sample_post(%{message_number: 42})
      tuples = Foglet.Markdown.render(body)

      parts = PostCard.reader_parts(post, tuples, width, theme(), index: 0, total: 1)
      flattened_lines = Enum.map(parts.body_lines, &flatten_text/1)

      assert length(parts.body_lines) > 1
      assert Enum.all?(flattened_lines, &String.starts_with?(&1, "│"))
      refute Enum.any?(flattened_lines, &String.contains?(&1, body))
      assert Enum.any?(flattened_lines, &String.contains?(&1, "alpha beta"))
      assert Enum.any?(flattened_lines, &String.contains?(&1, "lambda mu"))
    end

    test "narrow widths still return body lines without raising" do
      post = sample_post(%{message_number: 42})

      parts =
        PostCard.reader_parts(post, Foglet.Markdown.render("Hello"), 1, theme(),
          index: 0,
          total: 1
        )

      assert is_list(parts.body_lines)
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
      assert length(result) == 5
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
    test "no hardcoded color atoms appear anywhere in the tree (IN-03)" do
      post = sample_post(%{body: "A **bold** post with `code` and *italics*."})
      result = PostCard.render(post, 80, theme())
      serialized = inspect(result, printable_limit: :infinity, limit: :infinity)

      for color <- color_names() do
        refute color_atom_leaked?(serialized, color), "PostCard leaked :#{color}"
      end
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
