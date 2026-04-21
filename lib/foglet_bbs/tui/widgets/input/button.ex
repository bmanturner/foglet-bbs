defmodule Foglet.TUI.Widgets.Input.Button do
  @moduledoc """
  Themed button widget (D-02, D-13, D-16).

  Stateless — caller supplies label + role + state flags on every render.
  Wraps the conceptual surface of `Raxol.UI.Components.Input.Button`
  but does NOT delegate (D-16 — no state struct needed; we render
  a themed `text/2` directly).

  Honours:
    * D-07/D-09 — colors come from theme slots only
    * D-13     — `theme:` is an explicit keyword arg
    * D-16     — no state struct (purely stateless)

  UI-SPEC contract:
    :primary   → fg: theme.accent.fg,  style: [:bold]
    :danger    → fg: theme.error.fg,   style: [:bold]
    :success   → fg: theme.primary.fg, style: [:bold]
    :secondary → fg: theme.primary.fg, style: []
    disabled   → fg: theme.dim.fg,     style: [:dim] (any role)
  """

  import Raxol.Core.Renderer.View
  alias Foglet.TUI.Theme

  @default_role :secondary

  @type role :: :primary | :secondary | :danger | :success

  @doc """
  Renders a button label.

  Options:
    * `:role` — `:primary | :secondary | :danger | :success` (default `#{inspect(@default_role)}`)
    * `:disabled` — boolean (default `false`)
    * `:shortcut` — optional string hint (e.g., `"Ctrl+S"`)
    * `:theme` — required `%Foglet.TUI.Theme{}` struct
  """
  @spec render(String.t(), keyword()) :: any()
  def render(label, opts) when is_binary(label) and is_list(opts) do
    role = Keyword.get(opts, :role, @default_role)
    disabled = Keyword.get(opts, :disabled, false)
    shortcut = Keyword.get(opts, :shortcut)
    %Theme{} = theme = Keyword.fetch!(opts, :theme)

    {fg, style} = role_style(role, disabled, theme)
    content = if shortcut, do: " #{label} (#{shortcut}) ", else: " #{label} "

    text(content, fg: fg, style: style)
  end

  defp role_style(_any, true, theme), do: {theme.dim.fg, [:dim]}
  defp role_style(:primary, false, theme), do: {theme.accent.fg, [:bold]}
  defp role_style(:danger, false, theme), do: {theme.error.fg, [:bold]}
  defp role_style(:success, false, theme), do: {theme.primary.fg, [:bold]}
  defp role_style(_secondary, false, theme), do: {theme.primary.fg, []}
end
