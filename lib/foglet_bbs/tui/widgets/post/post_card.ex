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
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Post.MarkdownBody

  @type post_like :: %{
          optional(:id) => any(),
          optional(:body) => String.t() | nil,
          optional(:inserted_at) => DateTime.t() | NaiveDateTime.t() | nil,
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
      max_lines: Keyword.get(opts, :max_lines, :all)
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

  # "By @handle · 2h ago" when both fields are present; degrades
  # gracefully when either is missing.
  defp author_line(post) do
    handle = get_handle(post)
    when_str = get_time_ago(post)

    case {handle, when_str} do
      {h, nil} when is_binary(h) -> "By @#{h}"
      {nil, t} when is_binary(t) -> "#{t} ago"
      {h, t} when is_binary(h) and is_binary(t) -> "By @#{h} · #{t} ago"
      _ -> "(post details unavailable)"
    end
  end

  defp get_handle(%{user: %{handle: h}}) when is_binary(h) and h != "", do: h
  defp get_handle(_), do: nil

  defp get_time_ago(%{inserted_at: %DateTime{} = dt}), do: TimeAgo.format(dt)

  defp get_time_ago(%{inserted_at: %NaiveDateTime{} = naive}) do
    dt = DateTime.from_naive!(naive, "Etc/UTC")
    TimeAgo.format(dt)
  end

  defp get_time_ago(_), do: nil
end
