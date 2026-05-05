defmodule Foglet.TUI.Widgets.Auth.AuthForm do
  @moduledoc """
  Stateless logged-out/auth-adjacent form shell.

  Provides the shared compact card frame used by login, password recovery,
  registration, and verification surfaces. Honors D-07/D-09/D-13/D-16 by
  routing colors through `Foglet.TUI.Theme`, accepting the theme explicitly,
  and keeping rendering pure over already-loaded state.
  """

  alias Foglet.TUI.{TextWidth, Theme}
  import Raxol.Core.Renderer.View

  @default_width 46
  @default_height 9

  @type panel_opt ::
          {:width, pos_integer()}
          | {:height, pos_integer()}
          | {:active?, boolean()}
          | {:title_prefix, String.t()}

  def default_width, do: @default_width

  @spec helper_text(String.t(), Theme.t(), pos_integer()) :: [map()]
  def helper_text(copy, theme, width) when is_binary(copy) and is_integer(width) and width > 0 do
    copy
    |> TextWidth.wrap(width)
    |> Enum.map(&text(&1, fg: theme.dim.fg))
  end

  @spec render(String.t(), list(), Theme.t(), [panel_opt()]) :: map()
  def render(title, children, theme, opts \\ []) when is_binary(title) and is_list(children) do
    width = Keyword.get(opts, :width, @default_width)
    height = Keyword.get(opts, :height, @default_height)
    active? = Keyword.get(opts, :active?, true)
    prefix = Keyword.get(opts, :title_prefix, "")

    border_fg = if active?, do: theme.border.fg, else: theme.dim.fg
    title_fg = if active?, do: theme.title.fg, else: theme.dim.fg

    %{
      type: :panel,
      attrs: %{
        title: prefix <> title,
        title_attrs: %{fg: title_fg},
        border: :single,
        border_fg: border_fg,
        width: width,
        height: height
      },
      children: [
        column style: %{gap: 0, padding: 1} do
          children
        end
      ]
    }
  end

  @spec centered(any(), map(), Theme.t(), non_neg_integer()) :: any()
  def centered(panel, state, theme, panel_height) do
    {_, terminal_height} = Map.get(state, :terminal_size, {80, 24})
    available = max(terminal_height - 8, 1)
    top_padding = div(max(available - panel_height, 0), 2)
    pad = text(" ", fg: theme.primary.fg)

    column style: %{gap: 0, align_items: :center} do
      List.duplicate(pad, top_padding) ++ [panel]
    end
  end
end
