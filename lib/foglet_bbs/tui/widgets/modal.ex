defmodule Foglet.TUI.Widgets.Modal do
  @moduledoc """
  Modal widget body for errors, info, warnings, and confirmation prompts (D-20).

  This module renders the BODY of a modal (title, divider, message, key hints).
  Positioning/overlay centering is handled by `Foglet.TUI.App.render_modal_overlay/2`.

  Types:
    * :info    — neutral message with [Enter] OK hint
    * :error   — red-accent message with [Enter] OK hint
    * :warning — yellow-accent message with [Enter] OK hint
    * :confirm — message + [Y]es / [N]o hints

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

  @type modal_spec :: %{
          required(:message) => String.t(),
          optional(:type) => :info | :error | :warning | :confirm,
          optional(:title) => String.t(),
          optional(:on_confirm) => (map() -> any()) | :dismiss_modal,
          optional(:on_cancel) => (map() -> any()) | :dismiss_modal
        }

  @wrap_width 50

  @spec render(modal_spec()) :: any()
  def render(%{message: msg} = spec) do
    type = Map.get(spec, :type, :info)
    title = Map.get(spec, :title, title_for(type))
    color = color_for(type)

    wrapped_lines =
      msg
      |> word_wrap(@wrap_width)
      |> Enum.map(fn line -> text(line, fg: color) end)

    column [] do
      [text(" #{title} ", style: [:bold]), divider()] ++
        wrapped_lines ++
        [text(key_hint_for(type), style: [:dim])]
    end
  end

  defp title_for(:info), do: "Info"
  defp title_for(:error), do: "Error"
  defp title_for(:warning), do: "Warning"
  defp title_for(:confirm), do: "Confirm"

  defp color_for(:error), do: :red
  defp color_for(:warning), do: :yellow
  defp color_for(:confirm), do: :yellow
  defp color_for(_), do: :green

  defp key_hint_for(:confirm), do: "[Y] Yes   [N] No"
  defp key_hint_for(_), do: "[Enter] OK"

  # Wrap a string to <= max_width columns on whitespace boundaries.
  # Words longer than max_width are placed on their own line (not split mid-word).
  defp word_wrap(text, max_width) when is_binary(text) and is_integer(max_width) do
    text
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reduce([""], fn word, [current | rest] ->
      cond do
        current == "" ->
          [word | rest]

        String.length(current) + 1 + String.length(word) <= max_width ->
          ["#{current} #{word}" | rest]

        true ->
          [word, current | rest]
      end
    end)
    |> Enum.reverse()
  end
end
