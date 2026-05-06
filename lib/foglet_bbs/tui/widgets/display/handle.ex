defmodule Foglet.TUI.Widgets.Display.Handle do
  @moduledoc """
  Shared handle rendering for content and presence surfaces (D-07, D-09, D-13, D-16).

  This widget only colors explicit account handle data passed by callers. It does
  not parse arbitrary body text for @mentions, which keeps user-entered content
  under the markdown/plain-text renderers instead of recoloring handle-shaped
  substrings.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TerminalText
  alias Foglet.TUI.Theme

  @hex_color_format ~r/\A#[0-9A-Fa-f]{6}\z/
  @unknown_handle "unknown"

  def render(user_or_handle, %Theme{} = theme, opts \\ []) do
    handle = user_or_handle |> handle_text() |> sanitize_handle()
    prefix = Keyword.get(opts, :prefix, "@")
    style = Keyword.get(opts, :style, [:bold])

    text(prefix <> handle, fg: color_for(user_or_handle, theme), style: style)
  end

  @spec render_plain(String.t(), Theme.t()) :: map()
  def render_plain(content, %Theme{} = theme) when is_binary(content) do
    text(content, fg: theme.primary.fg)
  end

  @spec swatch(String.t() | nil, Theme.t(), Keyword.t()) :: map()
  def swatch(color, %Theme{} = theme, opts \\ []) do
    glyph = Keyword.get(opts, :glyph, "██")
    text(glyph, fg: color_for(%{handle_color: color}, theme), style: [:bold])
  end

  @spec color_for(map() | String.t() | nil, Theme.t()) :: String.t() | nil
  def color_for(user_or_color, %Theme{} = theme) do
    color =
      cond do
        is_binary(user_or_color) ->
          user_or_color

        is_map(user_or_color) ->
          Map.get(user_or_color, :handle_color) || Map.get(user_or_color, "handle_color")

        true ->
          nil
      end

    if valid_color?(color), do: color, else: theme.accent.fg
  end

  @spec valid_color?(term()) :: boolean()
  def valid_color?(color) when is_binary(color), do: Regex.match?(@hex_color_format, color)
  def valid_color?(_color), do: false

  @spec handle_text(map() | String.t() | nil) :: String.t()
  def handle_text(handle) when is_binary(handle) and handle != "", do: handle

  def handle_text(user) when is_map(user) do
    case Map.get(user, :handle) || Map.get(user, "handle") do
      handle when is_binary(handle) and handle != "" -> handle
      _other -> @unknown_handle
    end
  end

  def handle_text(_other), do: @unknown_handle

  defp sanitize_handle(handle) do
    handle
    |> TerminalText.sanitize_plain_text()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> case do
      "" -> @unknown_handle
      sanitized -> sanitized
    end
  end
end
