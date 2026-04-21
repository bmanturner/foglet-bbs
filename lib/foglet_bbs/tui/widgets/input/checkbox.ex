defmodule Foglet.TUI.Widgets.Input.Checkbox do
  @moduledoc """
  Themed checkbox widget (D-02, D-13, D-16).

  Stateless — caller passes `:checked?` on every render. Wraps the
  conceptual surface of `Raxol.UI.Components.Input.Checkbox` but does
  NOT delegate (D-16 — the toggle state lives in the parent screen).

  Honours:
    * D-07/D-09 — colors come from theme slots only
    * D-13     — `theme:` is an explicit keyword arg
    * D-16     — no state struct (purely stateless)

  UI-SPEC contract:
    checked? + !disabled  → fg: theme.selected.fg
    !checked? + !disabled → fg: theme.unselected.fg
    disabled (any)        → fg: theme.dim.fg, style: [:dim]
    marker                → `@on_marker` or `@off_marker` preceding the label
  """

  import Raxol.Core.Renderer.View
  alias Foglet.TUI.Theme

  @on_marker "[x]"
  @off_marker "[ ]"

  @doc """
  Renders a themed checkbox.

  Options:
    * `:checked?` — boolean (required)
    * `:disabled` — boolean (default `false`)
    * `:theme`    — required `%Foglet.TUI.Theme{}` struct

  Example:
      Checkbox.render("Remember me", checked?: true, theme: theme)
  """
  @spec render(String.t(), keyword()) :: any()
  def render(label, opts) when is_binary(label) and is_list(opts) do
    checked? = Keyword.fetch!(opts, :checked?)
    disabled = Keyword.get(opts, :disabled, false)
    %Theme{} = theme = Keyword.fetch!(opts, :theme)

    {fg, style} = style_for(checked?, disabled, theme)
    marker = if checked?, do: @on_marker, else: @off_marker

    text("#{marker} #{label}", fg: fg, style: style)
  end

  defp style_for(_checked?, true, theme), do: {theme.dim.fg, [:dim]}
  defp style_for(true, false, theme), do: {theme.selected.fg, []}
  defp style_for(false, false, theme), do: {theme.unselected.fg, []}
end
