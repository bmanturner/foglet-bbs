defmodule Foglet.TUI.Widgets.Modal do
  @moduledoc """
  Modal widget body for errors, info, warnings, and confirmation prompts (D-20).

  This module renders the BODY of a modal (title, divider, message, key hints).
  Positioning/overlay centering is handled by `Foglet.TUI.App.render_modal_overlay/2`.

  Types:
    * :info    — neutral message with [Enter] OK hint
    * :error   — error-slot-colored message with [Enter] OK hint
    * :warning — warning-slot-colored message with [Enter] OK hint
    * :confirm — warning-slot-colored message + [Y]es / [N]o hints

  Modal spec shape (used by callers dispatching {:show_modal, spec}):

      %{
        type: :info | :error | :warning | :confirm,
        title: "Optional Title",           # defaults based on type
        message: "Body text here.",
        on_confirm: fn state -> ... end,   # :confirm only — called on Y
        on_cancel: fn state -> ... end     # :confirm only — called on N/Esc
      }

  `on_confirm` / `on_cancel` may also be the atom `:dismiss_modal` as a shorthand.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Modal.Form

  @type modal_spec :: %{
          required(:message) => String.t(),
          optional(:type) => :info | :error | :warning | :confirm,
          optional(:title) => String.t(),
          optional(:on_confirm) => (map() -> any()) | :dismiss_modal,
          optional(:on_cancel) => (map() -> any()) | :dismiss_modal
        }

  @wrap_width 50

  @spec render(modal_spec() | Foglet.TUI.Modal.t(), Theme.t()) :: any()
  def render(%Foglet.TUI.Modal{type: :form, message: %Form{} = form}, %Theme{} = theme) do
    Form.render(form, theme: theme)
  end

  def render(%Foglet.TUI.Modal{message: msg} = spec, %Theme{} = theme) do
    type = spec.type || :info
    title = spec.title || title_for(type)
    msg_fg = color_for_type(type, theme)

    wrapped_lines =
      msg
      |> word_wrap(@wrap_width)
      |> Enum.map(fn line -> text(line, fg: msg_fg) end)

    column [] do
      [text(" #{title} ", fg: theme.title.fg, style: [:bold]), divider()] ++
        wrapped_lines ++
        [text(key_hint_for(type), fg: theme.dim.fg)]
    end
  end

  defp title_for(:info), do: "Info"
  defp title_for(:error), do: "Error"
  defp title_for(:warning), do: "Warning"
  defp title_for(:confirm), do: "Confirm"

  defp color_for_type(:error, %Theme{} = theme), do: theme.error.fg
  defp color_for_type(:warning, %Theme{} = theme), do: theme.warning.fg
  defp color_for_type(:confirm, %Theme{} = theme), do: theme.warning.fg
  defp color_for_type(_info, %Theme{} = theme), do: theme.primary.fg

  defp key_hint_for(:confirm), do: "[Y] Yes   [N] No"
  defp key_hint_for(_), do: "[Enter] OK"

  # Wrap a string to <= max_width columns, preserving whitespace word breaks
  # while chunking oversized tokens so modal bodies cannot overflow.
  defp word_wrap(text, max_width) when is_binary(text) and is_integer(max_width) do
    text
    |> String.split(~r/\s+/, trim: true)
    |> Enum.flat_map(&word_chunks(&1, max_width))
    |> Enum.reduce([""], fn word, [current | rest] ->
      cond do
        current == "" ->
          [word | rest]

        TextWidth.display_width(current) + 1 + TextWidth.display_width(word) <= max_width ->
          ["#{current} #{word}" | rest]

        true ->
          [word, current | rest]
      end
    end)
    |> Enum.reverse()
  end

  defp word_chunks("", _max_width), do: []

  defp word_chunks(word, max_width) do
    if TextWidth.display_width(word) <= max_width do
      [word]
    else
      {chunk, rest} = TextWidth.split_at(word, max_width)

      [chunk | word_chunks(rest, max_width)]
    end
  end
end
