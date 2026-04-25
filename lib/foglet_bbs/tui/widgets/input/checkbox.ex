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

  Visual contract:
    checked? + !disabled  → `✓`, fg: theme.success.fg
    !checked? + !disabled → `◇`, fg: theme.unselected.fg
    error                 → `×`, fg: theme.error.fg
    disabled (any)        → fg: theme.dim.fg, style: [:dim]
    ASCII compatibility   → `[x]` / `[ ]` with `marker_style: :ascii`
  """

  import Raxol.Core.Renderer.View
  alias Foglet.TUI.Theme

  @semantic_on_marker "✓"
  @semantic_off_marker "◇"
  @error_marker "×"
  @ascii_on_marker "[x]"
  @ascii_off_marker "[ ]"

  @doc """
  Renders a themed checkbox.

  Options:
    * `:checked?` — boolean (required)
    * `:disabled` — boolean (default `false`)
    * `:error` — boolean (default `false`)
    * `:marker_style` — `:semantic` (default) or `:ascii`
    * `:theme`    — required `%Foglet.TUI.Theme{}` struct

  Example:
      Checkbox.render("Remember me", checked?: true, theme: theme)
  """
  @spec render(String.t(), keyword()) :: any()
  def render(label, opts) when is_binary(label) and is_list(opts) do
    checked? = Keyword.fetch!(opts, :checked?)
    disabled = Keyword.get(opts, :disabled, false)
    error? = Keyword.get(opts, :error, false)
    marker_style = Keyword.get(opts, :marker_style, :semantic)
    %Theme{} = theme = Keyword.fetch!(opts, :theme)

    {fg, style} = style_for(checked?, disabled, error?, theme)
    marker = marker_for(checked?, error?, marker_style)

    text("#{marker} #{label}", fg: fg, style: style)
  end

  defp style_for(_checked?, true, _error?, theme), do: {theme.dim.fg, [:dim]}
  defp style_for(_checked?, false, true, theme), do: {theme.error.fg, [:bold]}
  defp style_for(true, false, false, theme), do: {theme.success.fg, [:bold]}
  defp style_for(false, false, false, theme), do: {theme.unselected.fg, []}

  defp marker_for(_checked?, true, :semantic), do: @error_marker
  defp marker_for(true, _error?, :ascii), do: @ascii_on_marker
  defp marker_for(false, _error?, :ascii), do: @ascii_off_marker
  defp marker_for(true, _error?, _semantic), do: @semantic_on_marker
  defp marker_for(false, _error?, _semantic), do: @semantic_off_marker
end
