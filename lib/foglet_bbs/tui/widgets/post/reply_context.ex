defmodule Foglet.TUI.Widgets.Post.ReplyContext do
  @moduledoc """
  Scrollable reply-context modal body for inspecting a replied-to post.

  Stateless widget honoring D-07/D-09/D-13/D-16: callers pass theme explicitly,
  colors route through `Foglet.TUI.Theme`, and screen reducers own domain work.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Post.PostCard

  @default_visible_body_rows 8
  @modal_post_index 0
  @modal_post_total 1

  defstruct post: nil,
            body_tuples: [],
            scroll_top: 0,
            visible_body_rows: @default_visible_body_rows,
            upvote?: false,
            profile?: false,
            status: nil

  @type t :: %__MODULE__{
          post: map(),
          body_tuples: list(),
          scroll_top: non_neg_integer(),
          visible_body_rows: pos_integer(),
          upvote?: boolean(),
          profile?: boolean(),
          status: term()
        }

  @spec new(map(), list(), keyword()) :: t()
  def new(post, body_tuples, opts \\ []) when is_map(post) and is_list(body_tuples) do
    visible_body_rows = Keyword.get(opts, :visible_body_rows, @default_visible_body_rows)

    %__MODULE__{
      post: post,
      body_tuples: body_tuples,
      scroll_top: Keyword.get(opts, :scroll_top, 0),
      visible_body_rows: max(visible_body_rows || @default_visible_body_rows, 1),
      upvote?: Keyword.get(opts, :upvote?, false),
      profile?: Keyword.get(opts, :profile?, false),
      status: Keyword.get(opts, :status)
    }
    |> clamp_scroll()
  end

  @spec replace_post(t(), map(), list()) :: t()
  def replace_post(%__MODULE__{} = context, post, body_tuples)
      when is_map(post) and is_list(body_tuples) do
    %{context | post: post, body_tuples: body_tuples}
    |> clamp_scroll()
  end

  @spec scroll(t(), integer()) :: t()
  def scroll(%__MODULE__{} = context, delta) when is_integer(delta) do
    %{context | scroll_top: context.scroll_top + delta}
    |> clamp_scroll()
  end

  @spec render(t(), Theme.t(), keyword()) :: term()
  def render(%__MODULE__{} = context, %Theme{} = theme, opts \\ []) do
    width = opts |> Keyword.get(:width, 60) |> max(28)

    parts =
      PostCard.reader_parts(context.post, context.body_tuples, width, theme,
        index: @modal_post_index,
        total: @modal_post_total
      )

    visible_body =
      parts.body_lines
      |> Enum.slice(context.scroll_top, context.visible_body_rows)

    column style: %{gap: 0} do
      Enum.reject(
        [
          title_row(theme),
          parts.header,
          parts.progress,
          scroll_status(context, parts.body_lines, width, theme)
        ] ++ visible_body ++ [footer_row(context, theme)],
        &is_nil/1
      )
    end
  end

  defp title_row(theme) do
    row style: %{gap: 0} do
      [
        text("▌ ", fg: theme.accent.fg),
        text("Reply context", fg: theme.title.fg, style: [:bold])
      ]
    end
  end

  defp scroll_status(%__MODULE__{} = context, body_lines, width, theme) do
    total = length(body_lines)

    label =
      cond do
        total <= context.visible_body_rows ->
          "Full post shown"

        context.scroll_top + context.visible_body_rows >= total ->
          "End of replied-to post"

        true ->
          first = context.scroll_top + 1
          last = min(context.scroll_top + context.visible_body_rows, total)
          "Lines #{first}-#{last}/#{total}"
      end

    text(TextWidth.truncate(label, max(width - 2, 1)), fg: theme.dim.fg)
  end

  defp footer_row(%__MODULE__{} = context, theme) do
    commands =
      [
        {"↑↓", "Scroll", true},
        {"Esc", "Close", true},
        {"U", "Upvote", context.upvote?},
        {"V", "Profile unavailable here", context.profile?}
      ]
      |> Enum.filter(fn {_key, _label, show?} -> show? end)
      |> Enum.flat_map(fn {key, label, _show?} ->
        [
          text("[#{key}]", fg: theme.accent.fg, style: [:bold]),
          text(" #{label}  ", fg: theme.dim.fg)
        ]
      end)

    row style: %{gap: 0} do
      commands
    end
  end

  defp clamp_scroll(%__MODULE__{} = context) do
    body_count = body_line_count(context)
    max_scroll = max(body_count - context.visible_body_rows, 0)
    %{context | scroll_top: context.scroll_top |> max(0) |> min(max_scroll)}
  end

  defp body_line_count(%__MODULE__{} = context) do
    body_lines =
      context.post
      |> Map.get(:body, "")
      |> to_string()
      |> String.split("\n")
      |> length()

    max(length(context.body_tuples), body_lines)
  end
end
