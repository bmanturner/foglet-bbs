defmodule Foglet.TUI.Screens.Account.SSHKeysSurface do
  @moduledoc """
  Pure renderer for the Account SSH KEYS tab.

  Renders loaded SSH key metadata only. Raw OpenSSH public-key material is
  intentionally omitted from the list surface.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Screens.Account.SSHKeysState
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.List.{ListRow, SelectionList}
  alias Foglet.TUI.Widgets.Progress.Spinner

  @key_hints "A Add   R Refresh   D Revoke   ↑/↓ Select"
  @empty_state "No SSH keys registered yet."

  @spec render(SSHKeysState.t(), Theme.t()) :: any()
  def render(%SSHKeysState{items: nil}, %Theme{} = theme), do: render_loading(theme)

  def render(%SSHKeysState{} = state, %Theme{} = theme) do
    column style: %{gap: 1} do
      [
        maybe_status(state.status_message, theme),
        maybe_errors(state.errors, theme),
        maybe_form(state, theme),
        key_rows(state.items, state.selected_index, theme),
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
    |> Enum.map(fn
      {:general, message} -> to_string(message)
      {field, message} -> "#{field} error: #{message}"
    end)
    |> Enum.join("; ")
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

  defp key_rows([], _selected_index, theme), do: text(@empty_state, fg: theme.dim.fg)

  defp key_rows(items, selected_index, theme) when is_list(items) do
    SelectionList.render(items, selected_index, fn {item, _idx, selected?} ->
      item
      |> row_label()
      |> ListRow.render(selected?, theme)
    end)
  end

  defp row_label(item) do
    [
      field(item, :label),
      field(item, :fingerprint),
      "created: #{timestamp_field(item, :inserted_at)}",
      last_used_field(item)
    ]
    |> Enum.join(" | ")
  end

  defp last_used_field(item) do
    case Map.get(item, :last_used_at) do
      nil -> "Never used"
      timestamp -> "last used: #{format_timestamp(timestamp)}"
    end
  end

  defp field(item, key) do
    item
    |> Map.get(key)
    |> to_string()
  end

  defp timestamp_field(item, key), do: item |> Map.get(key) |> format_timestamp()

  defp format_timestamp(%DateTime{} = timestamp),
    do: Calendar.strftime(timestamp, "%Y-%m-%d %H:%M:%SZ")

  defp format_timestamp(nil), do: ""
  defp format_timestamp(other), do: to_string(other)
end
