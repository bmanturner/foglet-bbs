defmodule Foglet.TUI.Screens.Account.SSHKeysSurface do
  @moduledoc """
  Pure renderer for the Account SSH KEYS tab (Phase 25, Plan 02).

  Renders the key list via `ConsoleTable.render/2` (D-05).
  Raw OpenSSH public-key material is intentionally omitted from the list surface.

  Per D-12 / R8: no hardcoded color atoms — all colors via `theme.<slot>`.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Screens.Account.SSHKeysState
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Display.ConsoleTable
  alias Foglet.TUI.Widgets.Progress.Spinner

  @key_hints "A Add   R Refresh   D Revoke   ↑/↓ Select"

  @spec render(SSHKeysState.t(), Theme.t()) :: any()
  def render(%SSHKeysState{items: nil}, %Theme{} = theme), do: render_loading(theme)

  def render(%SSHKeysState{} = state, %Theme{} = theme) do
    column style: %{gap: 1} do
      [
        maybe_status(state.status_message, theme),
        maybe_errors(state.errors, theme),
        maybe_form(state, theme),
        ConsoleTable.render(state.table, theme: theme),
        text(@key_hints, fg: theme.dim.fg)
      ]
      |> Enum.reject(&is_nil/1)
    end
  end

  defp render_loading(theme) do
    column style: %{gap: 0} do
      [
        row style: %{gap: 1} do
          [Spinner.render(0, style: :line, theme: theme), text("Loading…", fg: theme.dim.fg)]
        end
      ]
    end
  end

  defp maybe_status(nil, _theme), do: nil
  defp maybe_status(message, theme), do: text(message, fg: theme.accent.fg)

  defp maybe_errors(errors, _theme) when errors in [%{}, nil], do: nil

  defp maybe_errors(errors, theme) when is_map(errors) do
    errors
    |> Enum.map_join("; ", fn
      {:general, message} -> to_string(message)
      {field, message} -> "#{field} error: #{message}"
    end)
    |> text(fg: theme.error.fg)
  end

  defp maybe_form(%SSHKeysState{mode: :add, form: form, focus: focus}, theme) do
    label_marker = if focus == :label, do: ">", else: " "
    key_marker = if focus == :public_key, do: ">", else: " "

    column style: %{gap: 0} do
      [
        text("Add SSH key", fg: theme.accent.fg),
        text("#{label_marker} Label: #{Map.get(form, :label, "")}"),
        text("#{key_marker} Public key: #{Map.get(form, :public_key, "")}", fg: theme.dim.fg),
        text("Tab: field  Enter: add  Esc: cancel", fg: theme.dim.fg)
      ]
    end
  end

  defp maybe_form(_state, _theme), do: nil
end
