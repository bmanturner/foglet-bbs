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

  @key_hints "A Add key   R Refresh   D Revoke key   ↑/↓ Select"

  @spec render(SSHKeysState.t(), Theme.t(), non_neg_integer() | nil) :: any()
  def render(state, theme, available_width \\ nil)

  def render(%SSHKeysState{items: nil}, %Theme{} = theme, _available_width),
    do: render_loading(theme)

  def render(%SSHKeysState{mode: :confirm_revoke} = state, %Theme{} = theme, _available_width),
    do: render_confirm_revoke(state, theme)

  def render(%SSHKeysState{} = state, %Theme{} = theme, available_width) do
    column style: %{gap: 1} do
      [
        maybe_status(state.status_message, theme),
        maybe_errors(state.errors, theme),
        maybe_form(state, theme),
        ConsoleTable.render(table_for_width(state.table, available_width), theme: theme),
        text(@key_hints, fg: theme.dim.fg)
      ]
      |> Enum.reject(&is_nil/1)
    end
  end

  defp render_loading(theme) do
    column style: %{gap: 0} do
      [
        row style: %{gap: 1} do
          [
            Spinner.render(0, style: :line, theme: theme),
            text("Loading SSH keys…", fg: theme.dim.fg)
          ]
        end
      ]
    end
  end

  # Item 2 (FOG-130): destructive confirmation. Render label + fingerprint only;
  # raw public key material is never echoed.
  defp render_confirm_revoke(%SSHKeysState{confirm_target: target}, theme) do
    label = (target && target.label) || ""
    fingerprint = (target && target.fingerprint) || ""

    column style: %{gap: 1} do
      [
        text("Revoke SSH key?", fg: theme.accent.fg),
        text(
          "This removes #{label} from your account. Existing sessions stay open, but this key cannot sign in again.",
          fg: theme.primary.fg
        ),
        text("fingerprint: #{fingerprint}", fg: theme.dim.fg),
        text("Enter Revoke key   Esc Keep key", fg: theme.dim.fg)
      ]
    end
  end

  defp maybe_status(nil, _theme), do: nil
  defp maybe_status(message, theme), do: text(message, fg: theme.accent.fg)

  defp maybe_errors(errors, _theme) when errors in [%{}, nil], do: nil

  defp maybe_errors(errors, theme) when is_map(errors) do
    errors
    |> Enum.map_join("; ", fn
      {_field, message} -> to_string(message)
    end)
    |> text(fg: theme.error.fg)
  end

  defp maybe_form(%SSHKeysState{mode: :add, form: form, focus: focus}, theme) do
    label_marker = if focus == :label, do: ">", else: " "
    key_marker = if focus == :public_key, do: ">", else: " "
    public_key_value = truncate_key(Map.get(form, :public_key, ""))

    column style: %{gap: 0} do
      [
        text("Add SSH key", fg: theme.accent.fg),
        text("#{label_marker} Label: #{Map.get(form, :label, "")}"),
        text("  Name this key so you can recognize the machine later.", fg: theme.dim.fg),
        text("#{key_marker} Public key: #{public_key_value}", fg: theme.dim.fg),
        text("  Paste the full public key, starting with ssh-ed25519 or ssh-rsa.",
          fg: theme.dim.fg
        ),
        text("Tab Field   Enter Add key   Esc Cancel", fg: theme.dim.fg)
      ]
    end
  end

  defp maybe_form(_state, _theme), do: nil

  defp table_for_width(%ConsoleTable{} = table, available_width)
       when is_integer(available_width) and available_width > 0 do
    ConsoleTable.with_width(table, available_width)
  end

  defp table_for_width(%ConsoleTable{} = table, _available_width), do: table

  # Polish: keep a single pasted public key from blowing past the viewport.
  # Trim with an ellipsis once the value gets long; full validation still runs
  # on the underlying form value.
  defp truncate_key(value) when is_binary(value) do
    if String.length(value) > 60 do
      String.slice(value, 0, 57) <> "…"
    else
      value
    end
  end

  defp truncate_key(_other), do: ""
end
