defmodule Foglet.TUI.Widgets.Post.PostCard do
  @moduledoc """
  Complete per-post display card for Foglet BBS (WIDGET-01, RENDER-01).

  A PostCard is the integration unit PostReader calls once per displayed
  post. It owns the per-post layout — header + divider + body — but
  delegates the markdown body pipeline to `Post.MarkdownBody` so the
  newline-grouping fix (RENDER-01 root cause) lives in exactly one
  place.

  ## Layout

      ┌──────────────────────────────────┐
      │ Post 1 of 3                      │   <- dim
      │ By @sysop · 2h ago               │   <- dim
      │ ──────────────────────────────── │   <- border
      │ { rendered markdown body }       │   <- primary + style atoms
      └──────────────────────────────────┘

  ## Contract

      render(post, width, theme, opts \\\\ [])

      post — a Foglet.Posts.Post struct with :body, :inserted_at, :user preloaded
      width — terminal column count passed through to MarkdownBody
      theme — %Foglet.TUI.Theme{} for styled output
      opts:
        index:         non_neg_integer() (default 0)  — 0-based post index
        total:         pos_integer()     (default 1)  — total posts in thread
        scroll_offset: non_neg_integer() (default 0)  — passed to MarkdownBody
        max_lines:     pos_integer() | :all (default :all) — passed to MarkdownBody

  ## Memoization

  PostCard is pure (no internal cache). PostReader owns the cache in
  `state.screen_state[:post_reader][:render_cache]` keyed on
  `{post.id, width}`. See Plan 03 (PostReader integration). For callers
  that want to reuse a cached markdown parse, use `render_from_tuples/5`
  with pre-parsed tuples from `Foglet.Markdown.render/1`.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TimeAgo
  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Post.MarkdownBody

  @type post_like :: %{
          optional(:id) => any(),
          optional(:body) => String.t() | nil,
          optional(:message_number) => pos_integer() | nil,
          optional(:inserted_at) => DateTime.t() | NaiveDateTime.t() | nil,
          optional(:upvote_count) => non_neg_integer(),
          optional(:user) => map() | nil
        }

  @doc """
  Render a full post card from a post struct.

  The post's `body` field is parsed via `Foglet.Markdown.render/1`
  inside `Post.MarkdownBody.render/4`.
  """
  @spec render(post_like(), pos_integer(), Theme.t(), keyword()) :: any()
  def render(post, width, %Theme{} = theme, opts \\ [])
      when is_map(post) and is_integer(width) and width > 0 do
    body_text = Map.get(post, :body) || ""
    body_element = MarkdownBody.render(body_text, width, theme, body_opts(opts))

    assemble_card(post, theme, body_element, opts)
  end

  @doc """
  Render a full post card from pre-parsed markdown tuples.

  Used by PostReader when a render cache hit provides the tuple list
  — skipping the `Foglet.Markdown.render/1` call.
  """
  @spec render_from_tuples(
          post_like(),
          [MarkdownBody.tuple_entry()],
          pos_integer(),
          Theme.t(),
          keyword()
        ) :: any()
  def render_from_tuples(post, tuples, width, %Theme{} = theme, opts \\ [])
      when is_map(post) and is_list(tuples) and is_integer(width) and width > 0 do
    body_element = MarkdownBody.render_tuples(tuples, width, theme, body_opts(opts))
    assemble_card(post, theme, body_element, opts)
  end

  @doc """
  Render reader-oriented post parts from pre-parsed markdown tuples.

  Returns separate non-scrolling `:header` and `:progress` elements plus
  guttered `:body_lines` suitable for `Viewport.children`.
  """
  @spec reader_parts(
          post_like(),
          [MarkdownBody.tuple_entry()],
          pos_integer(),
          Theme.t(),
          keyword()
        ) :: %{
          header: any(),
          progress: any(),
          body_lines: [any()]
        }
  def reader_parts(post, tuples, width, %Theme{} = theme, opts \\ [])
      when is_map(post) and is_list(tuples) and is_integer(width) and width > 0 do
    index = Keyword.get(opts, :index, 0)
    total = Keyword.get(opts, :total, 1)

    %{
      header: reader_header(post, index, total, width, theme),
      progress:
        reader_progress(index, total, width, theme, Keyword.get(opts, :action_target?, false)),
      body_lines: reader_body_lines(tuples, width, theme)
    }
  end

  @doc """
  Render a post's body as a flat list of Raxol row elements — one per
  logical line — for use as `Raxol.UI.Components.Display.Viewport`
  children. The Viewport owns windowing/scroll-slicing.

  This function returns BODY ONLY — no "Post X of N" header, no author
  line, no divider. Callers wanting the header separately should build it
  with their own `text/2` calls using `theme.dim.fg` and `theme.border.fg`
  (see the `assemble_card/4` private helper for the current shape).

  Delegates to `MarkdownBody.render_tuples_as_lines/4`. The `opts` keyword
  is accepted for signature parity with `render_from_tuples/5`. The Viewport
  handles windowing; `wrap: true` remains a body-rendering concern because the
  reader must pass one already-wrapped visual row per child.
  """
  @spec render_body_lines(
          [MarkdownBody.tuple_entry()],
          pos_integer(),
          Theme.t(),
          keyword()
        ) :: [any()]
  def render_body_lines(tuples, width, %Theme{} = theme, opts \\ [])
      when is_list(tuples) and is_integer(width) and width > 0 do
    MarkdownBody.render_tuples_as_lines(tuples, width, theme, body_opts(opts))
  end

  @doc """
  Total number of logical body lines for the given post body string.
  Exposed so PostReader can compute scroll bounds without assembling
  the full card.
  """
  @spec body_line_count(String.t() | nil) :: non_neg_integer()
  def body_line_count(nil), do: 0
  def body_line_count(body) when is_binary(body), do: MarkdownBody.line_count(body)

  # ------------------------------------------------------------------
  # Private
  # ------------------------------------------------------------------

  defp body_opts(opts) do
    [
      scroll_offset: Keyword.get(opts, :scroll_offset, 0),
      max_lines: Keyword.get(opts, :max_lines, :all),
      wrap: Keyword.get(opts, :wrap, false)
    ]
  end

  defp assemble_card(post, theme, body_element, opts) do
    index = Keyword.get(opts, :index, 0)
    total = Keyword.get(opts, :total, 1)

    header_line_1 = text("Post #{index + 1} of #{total}", fg: theme.dim.fg)
    header_line_2 = text(author_line(post), fg: theme.dim.fg)
    header_divider = divider(char: "─", style: %{fg: theme.border.fg})

    column style: %{gap: 0} do
      [
        header_line_1,
        header_line_2,
        header_divider,
        body_element
      ]
    end
  end

  defp reader_header(post, index, total, width, theme) do
    text_width = reader_text_width(width)
    message_number = reader_message_number(post)
    handle = get_handle(post) || "unknown"
    age = reader_age(post)
    upvotes = reader_upvote_count(post)
    upvote_label = "▲#{upvotes}"
    position = "Post #{index + 1} of #{total}"
    message = "##{message_number}"
    handle_prefix = "@"
    separator = " • "

    fixed_width =
      [
        position,
        separator,
        message,
        separator,
        upvote_label,
        separator,
        handle_prefix,
        separator,
        age
      ]
      |> Enum.map(&TextWidth.display_width/1)
      |> Enum.sum()

    handle_width = max(text_width - fixed_width, 1)
    handle = TextWidth.truncate(handle, handle_width)

    nodes =
      if fixed_width + TextWidth.display_width(handle) <= text_width do
        [
          text(position, fg: theme.title.fg),
          text(separator, fg: theme.dim.fg),
          text(message, fg: theme.badge.fg),
          text(separator, fg: theme.dim.fg),
          text(upvote_label, fg: theme.badge.fg),
          text(separator, fg: theme.dim.fg),
          text(handle_prefix <> handle, fg: theme.accent.fg),
          text(separator, fg: theme.dim.fg),
          text(age, fg: theme.dim.fg)
        ]
      else
        [text(TextWidth.truncate(position, text_width), fg: theme.title.fg)]
      end

    row style: %{gap: 0} do
      nodes
    end
  end

  defp reader_progress(index, total, width, theme, true) do
    label = "Posts #{index + 1}/#{total}  ▶ Selected — R replies here"

    text(TextWidth.truncate(label, reader_text_width(width)),
      fg: theme.accent.fg
    )
  end

  defp reader_progress(index, total, width, theme, false) do
    text(TextWidth.truncate("Posts #{index + 1}/#{total}", reader_text_width(width)),
      fg: theme.dim.fg
    )
  end

  defp reader_body_lines(tuples, width, theme) do
    gutter = "│"
    gutter_gap = 1
    body_width = max(reader_text_width(width) - TextWidth.display_width(gutter) - gutter_gap, 1)

    tuples
    |> MarkdownBody.render_tuples_as_lines(body_width, theme, wrap: true)
    |> Enum.map(&clip_body_line(&1, body_width))
    |> Enum.map(fn body_line ->
      row style: %{gap: gutter_gap} do
        [text(gutter, fg: theme.border.fg), body_line]
      end
    end)
  end

  defp reader_text_width(width), do: max(width - 2, 1)

  defp clip_body_line(%{type: :flex, direction: :row, children: children} = row, width) do
    {children, _remaining_width} =
      Enum.map_reduce(children, width, fn child, remaining_width ->
        clipped = clip_body_line(child, remaining_width)
        {clipped, max(remaining_width - body_line_width(clipped), 0)}
      end)

    %{row | children: children}
  end

  defp clip_body_line(%{content: content} = element, width) when is_binary(content) do
    %{element | content: TextWidth.truncate(content, width)}
  end

  defp clip_body_line(%{text: text} = element, width) when is_binary(text) do
    %{element | text: TextWidth.truncate(text, width)}
  end

  defp clip_body_line(element, _width), do: element

  defp body_line_width(%{type: :flex, direction: :row, children: children}) do
    Enum.reduce(children, 0, fn child, width -> width + body_line_width(child) end)
  end

  defp body_line_width(%{content: content}) when is_binary(content),
    do: TextWidth.display_width(content)

  defp body_line_width(%{text: text}) when is_binary(text),
    do: TextWidth.display_width(text)

  defp body_line_width(_element), do: 0

  defp reader_message_number(%{message_number: number})
       when is_integer(number) and number > 0 do
    Integer.to_string(number)
  end

  defp reader_message_number(_post), do: "?"

  defp reader_upvote_count(%{upvote_count: count}) when is_integer(count) and count > 0,
    do: count

  defp reader_upvote_count(_post), do: 0

  defp reader_age(post) do
    case get_time_ago(post) do
      nil -> "age ?"
      time_ago -> "#{time_ago} ago"
    end
  end

  # "By @handle · 2h ago" when both fields are present; degrades
  # gracefully when either is missing. Returns "(post details unavailable)"
  # when neither handle nor timestamp is present.
  #
  # Exposed (via @doc false) so PostReader can render the non-scrolling
  # header line without duplicating the formatter. Pure formatter, no side
  # effects.
  @doc false
  @spec author_line(post_like()) :: String.t()
  def author_line(post) do
    handle = get_handle(post)
    when_str = get_time_ago(post)

    case {handle, when_str} do
      {h, nil} when is_binary(h) -> "By @#{h}"
      {nil, t} when is_binary(t) -> "#{t} ago"
      {h, t} when is_binary(h) and is_binary(t) -> "By @#{h} · #{t} ago"
      _ -> "(post details unavailable)"
    end
  end

  # Extract the author handle from a post-like map. Returns the handle
  # string when present and non-empty, else nil.
  #
  # Exposed (via @doc false) for reuse by PostReader and PostComposer.
  # The strict guard (is_binary(h) and h != "") means an empty-string
  # handle renders as nil rather than "@".
  @doc false
  @spec get_handle(post_like()) :: String.t() | nil
  def get_handle(%{user: %{handle: h}}) when is_binary(h) and h != "", do: h
  def get_handle(_), do: nil

  # Format the post's :inserted_at as a relative time string ("2h", "3d",
  # etc) via Foglet.TimeAgo. Returns nil when the field is missing or not
  # a DateTime / NaiveDateTime.
  #
  # Exposed (via @doc false) for reuse by PostReader.
  @doc false
  @spec get_time_ago(post_like()) :: String.t() | nil
  def get_time_ago(%{inserted_at: %DateTime{} = dt}), do: TimeAgo.format(dt)

  def get_time_ago(%{inserted_at: %NaiveDateTime{} = naive}) do
    dt = DateTime.from_naive!(naive, "Etc/UTC")
    TimeAgo.format(dt)
  end

  def get_time_ago(_), do: nil
end
