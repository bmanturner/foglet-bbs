defmodule Foglet.TUI.Widgets.Modal do
  @moduledoc """
  Modal widget body for errors, info, warnings, and confirmation prompts (D-20).

  This module renders the BODY of a modal (title, divider, message, key hints).
  Positioning/overlay centering is handled by `Foglet.TUI.App.render_modal_overlay/2`.

  Types:
    * :info    — info-slot-colored message with [Enter] OK hint
    * :success — success-slot-colored message with [Enter] OK hint
    * :error   — error-slot-colored message with [Enter] OK hint
    * :warning — warning-slot-colored message with [Enter] OK hint
    * :confirm — accent-slot-colored message + [Y]es / [N]o hints

  Modal spec shape (used by callers dispatching {:show_modal, spec}):

      %{
        type: :info | :success | :error | :warning | :confirm,
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
  alias Foglet.TUI.Widgets.Post.ReplyContext
  alias Foglet.TUI.Widgets.Profile.PublicProfileCard

  @type modal_spec :: %{
          required(:message) => String.t(),
          optional(:type) => :info | :success | :error | :warning | :confirm,
          optional(:title) => String.t(),
          optional(:on_confirm) => (map() -> any()) | :dismiss_modal,
          optional(:on_cancel) => (map() -> any()) | :dismiss_modal
        }

  @wrap_width 50

  @spec render(Foglet.TUI.Modal.t(), Theme.t()) :: any()
  @spec render(Foglet.TUI.Modal.t(), Theme.t(), keyword()) :: any()
  def render(modal, theme, opts \\ [])

  def render(%Foglet.TUI.Modal{type: :form, message: %Form{} = form}, %Theme{} = theme, opts) do
    Form.render(form, Keyword.put(opts, :theme, theme))
  end

  def render(%Foglet.TUI.Modal{message: %ReplyContext{} = context}, %Theme{} = theme, opts) do
    ReplyContext.render(context, theme, opts)
  end

  def render(
        %Foglet.TUI.Modal{
          type: :public_profile,
          message: %{profile: %Foglet.Accounts.PublicProfile{} = profile} = payload
        },
        %Theme{} = theme,
        _opts
      ) do
    PublicProfileCard.render(profile, theme, footer_hint: Map.get(payload, :footer_hint))
  end

  def render(
        %Foglet.TUI.Modal{message: %Foglet.Accounts.PublicProfile{} = profile},
        %Theme{} = theme,
        _opts
      ) do
    PublicProfileCard.render(profile, theme)
  end

  def render(%Foglet.TUI.Modal{message: msg} = spec, %Theme{} = theme, _opts) do
    type = spec.type || :info
    title = spec.title || title_for(type)
    msg_fg = color_for_type(type, theme)

    wrapped_lines =
      msg
      |> word_wrap(@wrap_width)
      |> Enum.map(fn line -> text(line, fg: msg_fg) end)

    column [] do
      [title_row(title, theme), divider_row(theme)] ++
        wrapped_lines ++
        [footer_row(type, theme)]
    end
  end

  defp title_for(:info), do: "Info"
  defp title_for(:success), do: "Success"
  defp title_for(:error), do: "Error"
  defp title_for(:warning), do: "Warning"
  defp title_for(:confirm), do: "Confirm"

  defp color_for_type(:info, %Theme{} = theme), do: theme.info.fg
  defp color_for_type(:success, %Theme{} = theme), do: theme.success.fg
  defp color_for_type(:error, %Theme{} = theme), do: theme.error.fg
  defp color_for_type(:warning, %Theme{} = theme), do: theme.warning.fg
  defp color_for_type(:confirm, %Theme{} = theme), do: theme.accent.fg
  defp color_for_type(_default, %Theme{} = theme), do: theme.primary.fg

  defp title_row(title, theme) do
    row style: %{gap: 0} do
      [
        text("▌ ", fg: theme.accent.fg),
        text(title, fg: theme.title.fg, style: [:bold])
      ]
    end
  end

  defp divider_row(theme), do: text(String.duplicate("─", @wrap_width), fg: theme.border.fg)

  defp footer_row(:confirm, theme) do
    row style: %{gap: 0} do
      [
        text("[Y]", fg: theme.accent.fg, style: [:bold]),
        text(" Yes   ", fg: theme.primary.fg),
        text("[N]", fg: theme.accent.fg, style: [:bold]),
        text(" No", fg: theme.dim.fg)
      ]
    end
  end

  defp footer_row(type, theme) do
    row style: %{gap: 0} do
      [
        text("[Enter]", fg: theme.accent.fg, style: [:bold]),
        text(" OK", fg: footer_label_color(type, theme))
      ]
    end
  end

  defp footer_label_color(:error, theme), do: theme.error.fg
  defp footer_label_color(:warning, theme), do: theme.warning.fg
  defp footer_label_color(:success, theme), do: theme.success.fg
  defp footer_label_color(_type, theme), do: theme.dim.fg

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
